# =============================================================================
# Azure / ARO Variables
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
  description = "Azure service principal client ID"
  type        = string
  default     = ""
}

variable "azure_client_secret" {
  description = "Azure service principal client secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "azure_tenant_id" {
  description = "Azure tenant ID"
  type        = string
  default     = ""
}

variable "aro_resource_group_name" {
  description = "Existing Azure resource group for ARO (OpenEnv provides this)"
  type        = string
}

variable "aro_cluster_name" {
  description = "Name of the ARO cluster"
  type        = string
  default     = "aro-east"
}

variable "aro_location" {
  description = "Azure region for ARO"
  type        = string
  default     = "eastus"
}

variable "aro_master_vm_size" {
  description = "VM size for ARO master nodes"
  type        = string
  default     = "Standard_D8s_v3"
}

variable "aro_worker_vm_size" {
  description = "VM size for ARO worker nodes"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "aro_worker_count" {
  description = "Number of ARO worker nodes"
  type        = number
  default     = 3
}

variable "pull_secret_path" {
  description = "Path to Red Hat pull secret JSON file"
  type        = string
}

# =============================================================================
# GCP / OSD Variables
# =============================================================================

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_credentials_file" {
  description = "Path to GCP service account credentials JSON"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for OSD"
  type        = string
  default     = "us-east1"
}

variable "osd_cluster_name" {
  description = "Name of the OSD cluster"
  type        = string
  default     = "osd-gcp"
}

variable "osd_machine_type" {
  description = "GCP machine type for OSD compute nodes"
  type        = string
  default     = "custom-4-16384"
}

variable "osd_compute_nodes" {
  description = "Number of OSD compute nodes"
  type        = number
  default     = 3
}

variable "ocm_token" {
  description = "OCM API token for OSD cluster management"
  type        = string
  sensitive   = true
}

# =============================================================================
# On-Prem Cluster
# =============================================================================

variable "onprem_kubeconfig" {
  description = "Path to existing on-prem cluster kubeconfig"
  type        = string
  default     = "/tmp/kubeconfig-onprem.yaml"
}

# =============================================================================
# Common
# =============================================================================

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    project     = "hybrid-cloud-demo"
    managed-by  = "terraform"
    environment = "demo"
  }
}
