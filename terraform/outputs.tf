# =============================================================================
# Cluster Outputs
# =============================================================================

output "aro_api_url" {
  description = "ARO cluster API URL"
  value       = module.aro.api_url
}

output "aro_console_url" {
  description = "ARO cluster console URL"
  value       = module.aro.console_url
}

output "aro_kubeadmin_password" {
  description = "ARO kubeadmin password"
  value       = module.aro.kubeadmin_password
  sensitive   = true
}

output "aro_kubeconfig_path" {
  description = "Path to ARO kubeconfig"
  value       = local_file.kubeconfig_aro.filename
}

output "osd_api_url" {
  description = "OSD cluster API URL"
  value       = module.osd.api_url
}

output "osd_console_url" {
  description = "OSD cluster console URL"
  value       = module.osd.console_url
}

output "osd_kubeconfig_path" {
  description = "Path to OSD kubeconfig"
  value       = local_file.kubeconfig_osd.filename
}

