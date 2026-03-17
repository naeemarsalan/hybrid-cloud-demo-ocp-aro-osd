# =============================================================================
# Azure VPN Gateway — Separate VNet + Peering to ARO VNet
# =============================================================================

# Reference existing ARO resources
data "azurerm_resource_group" "aro" {
  name = var.azure_resource_group
}

data "azurerm_virtual_network" "aro" {
  name                = var.azure_vnet_name
  resource_group_name = data.azurerm_resource_group.aro.name
}

# -----------------------------------------------------------------------------
# New VPN VNet (avoids modifying the existing ARO VNet)
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network" "vpn" {
  name                = "vpn-vnet"
  location            = var.azure_location
  resource_group_name = data.azurerm_resource_group.aro.name
  address_space       = [var.azure_vpn_vnet_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = data.azurerm_resource_group.aro.name
  virtual_network_name = azurerm_virtual_network.vpn.name
  address_prefixes     = [var.azure_gateway_subnet_prefix]
}

# -----------------------------------------------------------------------------
# VNet Peering: VPN VNet <-> ARO VNet
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network_peering" "vpn_to_aro" {
  name                         = "vpn-to-aro"
  resource_group_name          = data.azurerm_resource_group.aro.name
  virtual_network_name         = azurerm_virtual_network.vpn.name
  remote_virtual_network_id    = data.azurerm_virtual_network.aro.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true

  depends_on = [azurerm_virtual_network_gateway.vpn]
}

resource "azurerm_virtual_network_peering" "aro_to_vpn" {
  name                         = "aro-to-vpn"
  resource_group_name          = data.azurerm_resource_group.aro.name
  virtual_network_name         = data.azurerm_virtual_network.aro.name
  remote_virtual_network_id    = azurerm_virtual_network.vpn.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = true

  depends_on = [azurerm_virtual_network_gateway.vpn]
}

# -----------------------------------------------------------------------------
# VPN Gateway
# -----------------------------------------------------------------------------

resource "azurerm_public_ip" "vpn_gw" {
  name                = "vpn-gateway-ip"
  location            = var.azure_location
  resource_group_name = data.azurerm_resource_group.aro.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "vpn" {
  name                = "vpn-gateway"
  location            = var.azure_location
  resource_group_name = data.azurerm_resource_group.aro.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = var.azure_vpn_sku
  active_active       = false
  bgp_enabled         = true
  tags                = var.tags

  bgp_settings {
    asn = var.azure_bgp_asn

    peering_addresses {
      ip_configuration_name = "vpn-gw-ip-config"
      apipa_addresses       = ["169.254.21.1"]
    }
  }

  ip_configuration {
    name                          = "vpn-gw-ip-config"
    public_ip_address_id          = azurerm_public_ip.vpn_gw.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }
}

# -----------------------------------------------------------------------------
# Connection to GCP
# -----------------------------------------------------------------------------

resource "azurerm_local_network_gateway" "gcp" {
  name                = "gcp-local-gateway"
  location            = var.azure_location
  resource_group_name = data.azurerm_resource_group.aro.name
  gateway_address     = google_compute_ha_vpn_gateway.ha_vpn.vpn_interfaces[0].ip_address
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags

  bgp_settings {
    asn                 = var.gcp_bgp_asn
    bgp_peering_address = "169.254.21.2"
  }
}

resource "azurerm_virtual_network_gateway_connection" "to_gcp" {
  name                       = "azure-to-gcp"
  location                   = var.azure_location
  resource_group_name        = data.azurerm_resource_group.aro.name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn.id
  local_network_gateway_id   = azurerm_local_network_gateway.gcp.id
  shared_key                 = var.shared_secret
  bgp_enabled                = true
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
