variable "cluster_name" {
  description = "OSD cluster name"
  type        = string
  default     = "osd-gcp"
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-east1"
}

variable "ocm_token" {
  description = "OCM API token"
  type        = string
  sensitive   = true
}

variable "machine_type" {
  description = "GCP machine type for compute nodes"
  type        = string
  default     = "custom-4-16384"
}

variable "compute_nodes" {
  description = "Number of compute nodes"
  type        = number
  default     = 3
}

variable "osd_version" {
  description = "OSD OpenShift version (leave empty for latest)"
  type        = string
  default     = ""
}

variable "gcp_apis" {
  description = "GCP APIs to enable for OSD"
  type        = list(string)
  default = [
    "cloudapis.googleapis.com",
    "networksecurity.googleapis.com",
    "storage-api.googleapis.com",
    "storage-component.googleapis.com",
    "orgpolicy.googleapis.com",
    "iap.googleapis.com",
  ]
}
