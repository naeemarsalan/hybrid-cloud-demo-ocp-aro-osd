# =============================================================================
# On-Prem VPN Connections (gated by enable_onprem_vpn)
# =============================================================================

# -----------------------------------------------------------------------------
# Azure side — Local Network Gateway + Connection to On-Prem
# -----------------------------------------------------------------------------

resource "azurerm_local_network_gateway" "onprem" {
  count               = var.enable_onprem_vpn ? 1 : 0
  name                = "onprem-local-gateway"
  location            = var.azure_location
  resource_group_name = data.azurerm_resource_group.aro.name
  gateway_address     = var.onprem_public_ip
  address_space       = var.onprem_cidr_ranges
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway_connection" "to_onprem" {
  count                      = var.enable_onprem_vpn ? 1 : 0
  name                       = "azure-to-onprem"
  location                   = var.azure_location
  resource_group_name        = data.azurerm_resource_group.aro.name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn.id
  local_network_gateway_id   = azurerm_local_network_gateway.onprem[0].id
  shared_key                 = var.shared_secret
  bgp_enabled                = false
  tags                       = var.tags

  ipsec_policy {
    sa_lifetime      = 3600
    sa_datasize      = 0
    ipsec_encryption = "AES256"
    ipsec_integrity  = "SHA256"
    ike_encryption   = "AES256"
    ike_integrity    = "SHA256"
    dh_group         = "DHGroup14"
    pfs_group        = "PFS2048"
  }
}

# -----------------------------------------------------------------------------
# GCP side — External Gateway + Tunnel to On-Prem
# -----------------------------------------------------------------------------

resource "google_compute_external_vpn_gateway" "onprem" {
  count           = var.enable_onprem_vpn ? 1 : 0
  name            = "onprem-vpn-gateway"
  project         = var.gcp_project_id
  redundancy_type = "SINGLE_IP_INTERNALLY_REDUNDANT"

  interface {
    id         = 0
    ip_address = var.onprem_public_ip
  }
}

resource "google_compute_vpn_tunnel" "to_onprem" {
  count                           = var.enable_onprem_vpn ? 1 : 0
  name                            = "tunnel-to-onprem"
  region                          = var.gcp_region
  project                         = var.gcp_project_id
  vpn_gateway                     = google_compute_ha_vpn_gateway.ha_vpn.id
  vpn_gateway_interface           = 1
  peer_external_gateway           = google_compute_external_vpn_gateway.onprem[0].id
  peer_external_gateway_interface = 0
  shared_secret                   = var.shared_secret
  router                          = google_compute_router.vpn.id
  ike_version                     = 2
}

resource "google_compute_router_interface" "onprem" {
  count      = var.enable_onprem_vpn ? 1 : 0
  name       = "onprem-bgp-interface"
  router     = google_compute_router.vpn.name
  region     = var.gcp_region
  project    = var.gcp_project_id
  ip_range   = "169.254.22.2/30"
  vpn_tunnel = google_compute_vpn_tunnel.to_onprem[0].name
}

resource "google_compute_router_peer" "onprem" {
  count                     = var.enable_onprem_vpn ? 1 : 0
  name                      = "onprem-bgp-peer"
  router                    = google_compute_router.vpn.name
  region                    = var.gcp_region
  project                   = var.gcp_project_id
  peer_ip_address           = "169.254.22.1"
  peer_asn                  = var.onprem_bgp_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.onprem[0].name
}

# Firewall rule for on-prem traffic
resource "google_compute_firewall" "allow_onprem_vpn" {
  count   = var.enable_onprem_vpn ? 1 : 0
  name    = "allow-onprem-vpn"
  network = data.google_compute_network.osd.name
  project = var.gcp_project_id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = var.onprem_cidr_ranges
}
