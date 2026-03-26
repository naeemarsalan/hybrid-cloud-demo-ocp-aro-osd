# =============================================================================
# GCP HA VPN Gateway + Cloud Router
# =============================================================================

# Reference existing OSD VPC
data "google_compute_network" "osd" {
  name    = var.gcp_network_name
  project = var.gcp_project_id
}

# -----------------------------------------------------------------------------
# HA VPN Gateway
# -----------------------------------------------------------------------------

resource "google_compute_ha_vpn_gateway" "ha_vpn" {
  name    = "ha-vpn-gateway"
  region  = var.gcp_region
  project = var.gcp_project_id
  network = data.google_compute_network.osd.id
}

# -----------------------------------------------------------------------------
# Cloud Router
# -----------------------------------------------------------------------------

resource "google_compute_router" "vpn" {
  name    = "vpn-router"
  region  = var.gcp_region
  project = var.gcp_project_id
  network = data.google_compute_network.osd.id

  bgp {
    asn               = var.gcp_bgp_asn
    advertise_mode    = "DEFAULT"
  }
}

# -----------------------------------------------------------------------------
# Azure External VPN Gateway (represents Azure VPN Gateway in GCP)
# -----------------------------------------------------------------------------

resource "google_compute_external_vpn_gateway" "azure" {
  name            = "azure-vpn-gateway"
  project         = var.gcp_project_id
  redundancy_type = "SINGLE_IP_INTERNALLY_REDUNDANT"

  interface {
    id         = 0
    ip_address = azurerm_public_ip.vpn_gw.ip_address
  }
}

# -----------------------------------------------------------------------------
# VPN Tunnel to Azure
# -----------------------------------------------------------------------------

resource "google_compute_vpn_tunnel" "to_azure" {
  name                            = "tunnel-to-azure"
  region                          = var.gcp_region
  project                         = var.gcp_project_id
  vpn_gateway                     = google_compute_ha_vpn_gateway.ha_vpn.id
  vpn_gateway_interface           = 0
  peer_external_gateway           = google_compute_external_vpn_gateway.azure.id
  peer_external_gateway_interface = 0
  shared_secret                   = var.shared_secret
  router                          = google_compute_router.vpn.id
  ike_version                     = 2
}

# -----------------------------------------------------------------------------
# Router Interface & BGP Peer for Azure
# -----------------------------------------------------------------------------

resource "google_compute_router_interface" "azure" {
  name       = "azure-bgp-interface"
  router     = google_compute_router.vpn.name
  region     = var.gcp_region
  project    = var.gcp_project_id
  ip_range   = "169.254.21.2/30"
  vpn_tunnel = google_compute_vpn_tunnel.to_azure.name
}

resource "google_compute_router_peer" "azure" {
  name                      = "azure-bgp-peer"
  router                    = google_compute_router.vpn.name
  region                    = var.gcp_region
  project                   = var.gcp_project_id
  peer_ip_address           = "169.254.21.1"
  peer_asn                  = var.azure_bgp_asn
  advertised_route_priority = 100
  interface                 = google_compute_router_interface.azure.name
}

# -----------------------------------------------------------------------------
# Firewall Rules — Allow VPN traffic from Azure
# -----------------------------------------------------------------------------

resource "google_compute_firewall" "allow_azure_vpn" {
  name    = "allow-azure-vpn"
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

  source_ranges = ["10.0.0.0/22", var.azure_vpn_vnet_address_space]
}
