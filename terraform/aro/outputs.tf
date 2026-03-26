output "api_url" {
  description = "ARO cluster API URL"
  value       = azapi_resource.aro.output.properties.apiserverProfile.url
}

output "console_url" {
  description = "ARO cluster console URL"
  value       = azapi_resource.aro.output.properties.consoleProfile.url
}

output "kubeadmin_password" {
  description = "ARO kubeadmin password (retrieve via az aro list-credentials)"
  value       = ""
  sensitive   = true
}

output "kubeconfig_path" {
  description = "Path to ARO kubeconfig file"
  value       = "/tmp/kubeconfig-aro.yaml"
}

output "kubeconfig" {
  description = "ARO kubeconfig content"
  value       = data.local_file.kubeconfig.content
  sensitive   = true
}

output "vnet_name" {
  description = "ARO VNet name (for VPN peering)"
  value       = azurerm_virtual_network.aro.name
}

output "resource_group_name" {
  description = "ARO resource group name"
  value       = data.azurerm_resource_group.aro.name
}
