provider "azurerm" {
  features {}

  subscription_id = var.azure_subscription_id
  use_cli         = var.azure_use_cli

  client_id     = var.azure_use_cli ? null : var.azure_client_id
  client_secret = var.azure_use_cli ? null : var.azure_client_secret
  tenant_id     = var.azure_use_cli ? null : var.azure_tenant_id
}

provider "azapi" {
  subscription_id = var.azure_subscription_id
  use_cli         = var.azure_use_cli
}

provider "google" {
  credentials = file(var.gcp_credentials_file)
  project     = var.gcp_project_id
  region      = var.gcp_region
}
