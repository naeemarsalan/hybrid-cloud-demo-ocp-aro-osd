# =============================================================================
# ARO Cluster — Azure Red Hat OpenShift via azapi
# =============================================================================

# Use existing resource group (OpenEnv provides pre-allocated RG)
data "azurerm_resource_group" "aro" {
  name = var.resource_group_name
}

# VNet and Subnets
resource "azurerm_virtual_network" "aro" {
  name                = "${var.cluster_name}-vnet"
  location            = data.azurerm_resource_group.aro.location
  resource_group_name = data.azurerm_resource_group.aro.name
  address_space       = [var.vnet_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "master" {
  name                 = "${var.cluster_name}-master"
  resource_group_name  = data.azurerm_resource_group.aro.name
  virtual_network_name = azurerm_virtual_network.aro.name
  address_prefixes     = [var.master_subnet_prefix]

  service_endpoints = ["Microsoft.ContainerRegistry"]
}

resource "azurerm_subnet" "worker" {
  name                 = "${var.cluster_name}-worker"
  resource_group_name  = data.azurerm_resource_group.aro.name
  virtual_network_name = azurerm_virtual_network.aro.name
  address_prefixes     = [var.worker_subnet_prefix]

  service_endpoints = ["Microsoft.ContainerRegistry"]
}

# Register required Azure resource providers
resource "null_resource" "register_providers" {
  provisioner "local-exec" {
    command = <<-EOT
      az provider register -n Microsoft.RedHatOpenShift --wait
      az provider register -n Microsoft.Compute --wait
      az provider register -n Microsoft.Storage --wait
      az provider register -n Microsoft.Authorization --wait
    EOT
  }
}

# Get current Azure RP object ID for ARO
data "azurerm_client_config" "current" {}

# Grant ARO RP (f1dd0a37-89c6-4e07-bcd1-ffd3d43d8875) Network Contributor on VNet
resource "null_resource" "aro_rp_role_assignment" {
  depends_on = [azurerm_virtual_network.aro]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      ARO_RP_OID=$(az ad sp show --id "f1dd0a37-89c6-4e07-bcd1-ffd3d43d8875" --query id -o tsv)
      az role assignment create \
        --assignee-object-id "$ARO_RP_OID" \
        --assignee-principal-type ServicePrincipal \
        --role "Network Contributor" \
        --scope "${azurerm_virtual_network.aro.id}" 2>/dev/null || true
    EOT
  }
}

# ARO Cluster via azapi (no native azurerm resource)
resource "azapi_resource" "aro" {
  type      = "Microsoft.RedHatOpenShift/openShiftClusters@2023-11-22"
  name      = var.cluster_name
  location  = data.azurerm_resource_group.aro.location
  parent_id = data.azurerm_resource_group.aro.id
  tags      = var.tags

  body = {
    properties = {
      clusterProfile = {
        domain               = var.cluster_name
        fipsValidatedModules = "Disabled"
        pullSecret           = var.pull_secret
        resourceGroupId      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.cluster_name}-cluster-rg"
      }
      networkProfile = {
        podCidr     = "10.128.0.0/14"
        serviceCidr = "172.30.0.0/16"
      }
      masterProfile = {
        vmSize           = var.master_vm_size
        subnetId         = azurerm_subnet.master.id
        encryptionAtHost = "Disabled"
      }
      workerProfiles = [
        {
          name             = "worker"
          vmSize           = var.worker_vm_size
          diskSizeGB       = var.worker_disk_size_gb
          subnetId         = azurerm_subnet.worker.id
          count            = var.worker_count
          encryptionAtHost = "Disabled"
        }
      ]
      servicePrincipalProfile = {
        clientId     = var.service_principal_client_id
        clientSecret = var.service_principal_client_secret
      }
      apiserverProfile = {
        visibility = var.api_visibility
      }
      ingressProfiles = [
        {
          name       = "default"
          visibility = var.ingress_visibility
        }
      ]
    }
  }

  response_export_values = [
    "properties.apiserverProfile.url",
    "properties.consoleProfile.url",
  ]

  depends_on = [null_resource.register_providers, null_resource.aro_rp_role_assignment]

  timeouts {
    create = "90m"
    delete = "60m"
  }
}

# Extract cluster credentials and write kubeconfig
resource "null_resource" "kubeconfig" {
  triggers = {
    aro_id = azapi_resource.aro.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      RG="${var.resource_group_name}"
      NAME="${var.cluster_name}"

      # Get credentials
      CREDS=$(az aro list-credentials -g "$RG" -n "$NAME" -o json)
      ADMIN_USER=$(echo "$CREDS" | jq -r '.kubeadminUsername')
      ADMIN_PASS=$(echo "$CREDS" | jq -r '.kubeadminPassword')

      # Get API URL
      API_URL=$(az aro show -g "$RG" -n "$NAME" --query apiserverProfile.url -o tsv)

      # Login and write kubeconfig
      oc login "$API_URL" -u "$ADMIN_USER" -p "$ADMIN_PASS" --insecure-skip-tls-verify=true
      oc config view --minify --flatten > /tmp/kubeconfig-aro.yaml
      chmod 600 /tmp/kubeconfig-aro.yaml
    EOT
  }
}

# Read kubeconfig content for output
data "local_file" "kubeconfig" {
  filename   = "/tmp/kubeconfig-aro.yaml"
  depends_on = [null_resource.kubeconfig]
}
