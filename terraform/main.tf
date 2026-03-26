# =============================================================================
# Hybrid Cloud Demo — Root Module
# =============================================================================
# Creates ARO (Azure) + OSD (GCP) clusters.
# On-prem cluster is assumed to exist — user provides kubeconfig.

module "aro" {
  source = "./aro"

  resource_group_name            = var.aro_resource_group_name
  cluster_name                   = var.aro_cluster_name
  location                       = var.aro_location
  master_vm_size                 = var.aro_master_vm_size
  worker_vm_size                 = var.aro_worker_vm_size
  worker_count                   = var.aro_worker_count
  pull_secret                    = file(var.pull_secret_path)
  service_principal_client_id    = var.azure_client_id
  service_principal_client_secret = var.azure_client_secret
  tags                           = var.tags
}

module "osd" {
  source = "./osd"

  cluster_name   = var.osd_cluster_name
  gcp_project_id = var.gcp_project_id
  gcp_region     = var.gcp_region
  ocm_token      = var.ocm_token
  machine_type   = var.osd_machine_type
  compute_nodes  = var.osd_compute_nodes
}

# Write kubeconfig files for Ansible consumption
resource "local_file" "kubeconfig_aro" {
  content         = module.aro.kubeconfig
  filename        = "/tmp/kubeconfig-aro.yaml"
  file_permission = "0600"
}

resource "local_file" "kubeconfig_osd" {
  content         = module.osd.kubeconfig
  filename        = "/tmp/kubeconfig-osd.yaml"
  file_permission = "0600"
}
