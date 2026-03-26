# =============================================================================
# Azure Variables
# =============================================================================

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "azure_use_cli" {
  description = "Use az CLI auth instead of service principal"
  type        = bool
  default     = true
}

variable "azure_client_id" {
  description = "Azure service principal client ID (only when azure_use_cli = false)"
  type        = string
  default     = ""
}

variable "azure_client_secret" {
  description = "Azure service principal client secret (only when azure_use_cli = false)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "azure_tenant_id" {
  description = "Azure tenant ID (only when azure_use_cli = false)"
  type        = string
  default     = ""
}

variable "azure_resource_group" {
  description = "Azure resource group containing the ARO VNet"
  type        = string
  default     = "aro-rg"
}

variable "azure_location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "azure_vnet_name" {
  description = "Existing ARO VNet name"
  type        = string
  default     = "aro-vnet"
}

variable "azure_vpn_vnet_address_space" {
  description = "Address space for the new VPN VNet (separate from ARO VNet)"
  type        = string
  default     = "10.4.0.0/24"
}

variable "azure_gateway_subnet_prefix" {
  description = "CIDR for GatewaySubnet within the VPN VNet (/27 minimum)"
  type        = string
  default     = "10.4.0.0/27"
}

variable "azure_vpn_sku" {
  description = "Azure VPN Gateway SKU"
  type        = string
  default     = "VpnGw1"
}

variable "azure_bgp_asn" {
  description = "BGP ASN for Azure VPN Gateway"
  type        = number
  default     = 65515
}

# =============================================================================
# GCP Variables
# =============================================================================

variable "gcp_project_id" {
  description = "GCP project ID containing the OSD cluster"
  type        = string
  default     = "openenv-j4tbl"
}

variable "gcp_credentials_file" {
  description = "Path to GCP service account credentials JSON"
  type        = string
  default     = "../../osd/sa.json"
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-east1"
}

variable "gcp_network_name" {
  description = "Existing GCP VPC network name"
  type        = string
  default     = "osd-demo-z2vzk-network"
}

variable "gcp_bgp_asn" {
  description = "BGP ASN for GCP Cloud Router"
  type        = number
  default     = 65534
}

# =============================================================================
# On-Prem Variables
# =============================================================================

variable "enable_onprem_vpn" {
  description = "Enable on-prem VPN connections (set to true when on-prem endpoint is ready)"
  type        = bool
  default     = false
}

variable "onprem_public_ip" {
  description = "Public IP address of the on-prem VPN endpoint"
  type        = string
  default     = ""
}

variable "onprem_cidr_ranges" {
  description = "List of on-prem subnet CIDR ranges"
  type        = list(string)
  default     = ["192.168.0.0/16"]
}

variable "onprem_bgp_asn" {
  description = "BGP ASN for on-prem (only used if BGP is enabled with on-prem)"
  type        = number
  default     = 65500
}

# =============================================================================
# Shared Variables
# =============================================================================

variable "shared_secret" {
  description = "IPSec pre-shared key for all VPN tunnels"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    project     = "hybrid-cloud-demo"
    managed-by  = "terraform"
    environment = "demo"
  }
}
