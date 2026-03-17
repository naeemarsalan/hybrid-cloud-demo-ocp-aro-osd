# =============================================================================
# Azure Outputs
# =============================================================================

output "azure_vpn_gateway_public_ip" {
  description = "Public IP address of the Azure VPN Gateway"
  value       = azurerm_public_ip.vpn_gw.ip_address
}

output "azure_vpn_gateway_bgp_ip" {
  description = "BGP peering IP of the Azure VPN Gateway"
  value       = azurerm_virtual_network_gateway.vpn.bgp_settings[0].peering_addresses[0].default_addresses[0]
}

# =============================================================================
# GCP Outputs
# =============================================================================

output "gcp_ha_vpn_gateway_ips" {
  description = "Public IP addresses of the GCP HA VPN Gateway (2 interfaces)"
  value = [
    google_compute_ha_vpn_gateway.ha_vpn.vpn_interfaces[0].ip_address,
    google_compute_ha_vpn_gateway.ha_vpn.vpn_interfaces[1].ip_address,
  ]
}

output "gcp_bgp_peer_ip" {
  description = "GCP Cloud Router BGP IP for Azure peering"
  value       = google_compute_router_interface.azure.ip_range
}

# =============================================================================
# Tunnel Info
# =============================================================================

output "azure_to_gcp_connection_id" {
  description = "Azure VPN connection resource ID"
  value       = azurerm_virtual_network_gateway_connection.to_gcp.id
}

output "gcp_to_azure_tunnel_name" {
  description = "GCP VPN tunnel name"
  value       = google_compute_vpn_tunnel.to_azure.name
}

# =============================================================================
# On-Prem Configuration Snippet
# =============================================================================

output "onprem_ipsec_config" {
  description = "IPSec configuration for on-prem Libreswan/strongSwan"
  value       = <<-EOT

    # =========================================================================
    # On-Prem VPN Configuration
    # =========================================================================
    # Use these values to configure Libreswan or strongSwan on your on-prem host.
    #
    # Azure VPN Gateway:
    #   Public IP:  ${azurerm_public_ip.vpn_gw.ip_address}
    #   BGP ASN:    ${var.azure_bgp_asn}
    #   Remote CIDRs: 10.0.0.0/22 (ARO), ${var.azure_vpn_vnet_address_space} (VPN VNet)
    #
    # GCP HA VPN Gateway:
    #   Public IP 0: ${google_compute_ha_vpn_gateway.ha_vpn.vpn_interfaces[0].ip_address}
    #   Public IP 1: ${google_compute_ha_vpn_gateway.ha_vpn.vpn_interfaces[1].ip_address}
    #   BGP ASN:     ${var.gcp_bgp_asn}
    #   Remote CIDR: 10.0.0.0/16 (OSD VPC)
    #
    # --- Libreswan config (/etc/ipsec.d/hybrid-cloud.conf) ---
    #
    # conn onprem-to-azure
    #     authby=secret
    #     auto=start
    #     type=tunnel
    #     left=%defaultroute
    #     leftsubnets=<YOUR_ON_PREM_CIDRS>
    #     right=${azurerm_public_ip.vpn_gw.ip_address}
    #     rightsubnets={10.0.0.0/22 ${var.azure_vpn_vnet_address_space}}
    #     ike=aes256-sha2_256;modp2048
    #     esp=aes256-sha2_256;modp2048
    #     ikelifetime=28800s
    #     salifetime=3600s
    #     ikev2=yes
    #
    # conn onprem-to-gcp
    #     authby=secret
    #     auto=start
    #     type=tunnel
    #     left=%defaultroute
    #     leftsubnets=<YOUR_ON_PREM_CIDRS>
    #     right=${google_compute_ha_vpn_gateway.ha_vpn.vpn_interfaces[1].ip_address}
    #     rightsubnets=10.0.0.0/16
    #     ike=aes256-sha2_256;modp2048
    #     esp=aes256-sha2_256;modp2048
    #     ikelifetime=28800s
    #     salifetime=3600s
    #     ikev2=yes
    #
    # --- Libreswan secrets (/etc/ipsec.d/hybrid-cloud.secrets) ---
    #
    # %any ${azurerm_public_ip.vpn_gw.ip_address} : PSK "<YOUR_SHARED_SECRET>"
    # %any ${google_compute_ha_vpn_gateway.ha_vpn.vpn_interfaces[1].ip_address} : PSK "<YOUR_SHARED_SECRET>"
    #
    # =========================================================================
  EOT
}
