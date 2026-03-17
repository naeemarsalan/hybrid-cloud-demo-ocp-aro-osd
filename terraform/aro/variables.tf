variable "cluster_name" {
  description = "ARO cluster name"
  type        = string
  default     = "aro-east"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Existing Azure resource group name (OpenEnv pre-allocated)"
  type        = string
}

variable "vnet_address_space" {
  description = "VNet CIDR for ARO"
  type        = string
  default     = "10.0.0.0/22"
}

variable "master_subnet_prefix" {
  description = "Master subnet CIDR"
  type        = string
  default     = "10.0.0.0/23"
}

variable "worker_subnet_prefix" {
  description = "Worker subnet CIDR"
  type        = string
  default     = "10.0.2.0/23"
}

variable "master_vm_size" {
  description = "VM size for master nodes"
  type        = string
  default     = "Standard_D8s_v3"
}

variable "worker_vm_size" {
  description = "VM size for worker nodes"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

variable "worker_disk_size_gb" {
  description = "Worker node OS disk size in GB"
  type        = number
  default     = 128
}

variable "pull_secret" {
  description = "Red Hat pull secret JSON content"
  type        = string
  sensitive   = true
}

variable "service_principal_client_id" {
  description = "Azure service principal client ID for ARO"
  type        = string
}

variable "service_principal_client_secret" {
  description = "Azure service principal client secret for ARO"
  type        = string
  sensitive   = true
}

variable "api_visibility" {
  description = "API server visibility (Public or Private)"
  type        = string
  default     = "Public"
}

variable "ingress_visibility" {
  description = "Ingress visibility (Public or Private)"
  type        = string
  default     = "Public"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
