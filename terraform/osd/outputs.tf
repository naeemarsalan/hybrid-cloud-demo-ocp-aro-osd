output "api_url" {
  description = "OSD cluster API URL"
  value       = data.external.cluster_info.result.api_url
}

output "console_url" {
  description = "OSD cluster console URL"
  value       = data.external.cluster_info.result.console_url
}

output "kubeconfig_path" {
  description = "Path to OSD kubeconfig file"
  value       = "/tmp/kubeconfig-osd.yaml"
}

output "kubeconfig" {
  description = "OSD kubeconfig content"
  value       = data.local_file.kubeconfig.content
  sensitive   = true
}

output "vpc_network_name" {
  description = "GCP VPC network name (for VPN)"
  value       = data.external.cluster_info.result.vpc_network_name
}
