terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.19.1"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "2.28.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "=3.4.3"
    }
  }
}

provider "azurerm" {
  features {}
  
  # These values can be set via environment variables from secret.env:
  # ARM_TENANT_ID, ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET
  # Load them by running: export $(grep -v '^#' secret.env | xargs)
  
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
}

# Variables for Azure authentication (values from secret.env)
variable "tenant_id" {
  description = "Azure Active Directory Tenant ID"
  type        = string
  default     = ""  # Will be set via ARM_TENANT_ID env var
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  default     = ""  # Will be set via ARM_SUBSCRIPTION_ID env var
}

variable "client_id" {
  description = "Service Principal Client ID (Application ID)"
  type        = string
  default     = ""  # Will be set via ARM_CLIENT_ID env var
}

variable "client_secret" {
  description = "Service Principal Client Secret"
  type        = string
  sensitive   = true
  default     = ""  # Will be set via ARM_CLIENT_SECRET env var
}

data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Variables for ABAC configuration
variable "allowed_pull_tags" {
  description = "List of image tags allowed for pull operations"
  type        = list(string)
  default     = ["latest", "v*", "prod-*"]
}

variable "allowed_push_repositories" {
  description = "List of repository names/prefixes allowed for push operations"
  type        = list(string)
  default     = ["web-app-sample", "approved/*", "prod/*"]
}

variable "allowed_delete_tags" {
  description = "List of image tag prefixes allowed for delete operations"
  type        = list(string)
  default     = ["dev-*", "test-*"]
}

resource "random_id" "main" {
  byte_length = 4
  prefix      = "notary-"
}

# southcentralus is the only region that supports signatures at this time.
resource "azurerm_resource_group" "example" {
  name     = "${random_id.main.hex}-rg"
  location = "southcentralus"
}

resource "azurerm_key_vault" "kv" {
  name                        = "${random_id.main.hex}-kv"
  location                    = azurerm_resource_group.example.location
  resource_group_name         = azurerm_resource_group.example.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
  
  # Enable RBAC authorization instead of access policies
  enable_rbac_authorization   = true
}

# Key Vault Certificates Officer - Full certificate management permissions
resource "azurerm_role_assignment" "kv_certificates_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azuread_client_config.current.object_id
  
  description = "Grants service principal full certificate management permissions"
}

# Key Vault Certificates User - Read certificate permissions
resource "azurerm_role_assignment" "kv_certificates_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Certificates User"
  principal_id         = data.azuread_client_config.current.object_id
  
  description = "Grants service principal certificate read permissions"
}

# Key Vault Crypto User - Cryptographic operations permissions
resource "azurerm_role_assignment" "kv_crypto_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = data.azuread_client_config.current.object_id
  
  description = "Grants service principal cryptographic operations permissions"
}

# ============================================================================
# Azure Container Registry with ABAC (Attribute-Based Access Control)
# ============================================================================
# This configuration uses ABAC to provide fine-grained access control to ACR.
# ABAC conditions are applied to role assignments to control access based on:
# - Image tags (e.g., only pull images tagged with 'latest', 'v*', or 'prod-*')
# - Repository names (e.g., only push to 'web-app-sample' or 'approved/*' repos)
# - Artifact properties (e.g., only delete 'dev-*' or 'test-*' tagged images)
#
# Benefits of ABAC:
# - Prevents accidental modification of production images
# - Enforces naming conventions and tagging standards
# - Provides least-privilege access at a granular level
# - Audit trail of access patterns and violations
# ============================================================================

resource "azurerm_container_registry" "acr" {
  name                    = replace("${random_id.main.hex}acr","-","")
  resource_group_name     = azurerm_resource_group.example.name
  location                = azurerm_resource_group.example.location
  sku                     = "Premium"
  admin_enabled           = false
  zone_redundancy_enabled = false
}

# ACR Pull role assignment with ABAC condition
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = data.azuread_client_config.current.object_id
  
  # ABAC condition: Allow pull only for images with specific tags
  condition = <<-EOT
    (
      (
        !(ActionMatches{'Microsoft.ContainerRegistry/registries/pull/read'})
      )
      OR
      (
        @Resource[Microsoft.ContainerRegistry/registries/artifacts/tag:tag] StringEquals 'latest'
        OR
        @Resource[Microsoft.ContainerRegistry/registries/artifacts/tag:tag] StringStartsWith 'v'
        OR
        @Resource[Microsoft.ContainerRegistry/registries/artifacts/tag:tag] StringStartsWith 'prod-'
      )
    )
  EOT
  
  condition_version = "2.0"
  
  description = "ABAC-based ACR pull access for approved image tags"
}

# ACR Push role assignment with ABAC condition
resource "azurerm_role_assignment" "acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = data.azuread_client_config.current.object_id
  
  # ABAC condition: Allow push only to specific repositories
  condition = <<-EOT
    (
      (
        !(ActionMatches{'Microsoft.ContainerRegistry/registries/push/write'})
      )
      OR
      (
        @Resource[Microsoft.ContainerRegistry/registries/repositories:name] StringEquals 'web-app-sample'
        OR
        @Resource[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWith 'approved/'
        OR
        @Resource[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWith 'prod/'
      )
    )
  EOT
  
  condition_version = "2.0"
  
  description = "ABAC-based ACR push access for approved repositories"
}

# ACR Delete role assignment with ABAC condition (optional - for cleanup)
resource "azurerm_role_assignment" "acr_delete" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrDelete"
  principal_id         = data.azuread_client_config.current.object_id
  
  # ABAC condition: Allow delete only for dev/test images
  condition = <<-EOT
    (
      (
        !(ActionMatches{'Microsoft.ContainerRegistry/registries/artifacts/delete'})
      )
      OR
      (
        @Resource[Microsoft.ContainerRegistry/registries/artifacts/tag:tag] StringStartsWith 'dev-'
        OR
        @Resource[Microsoft.ContainerRegistry/registries/artifacts/tag:tag] StringStartsWith 'test-'
        OR
        @Resource[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWith 'sandbox/'
      )
    )
  EOT
  
  condition_version = "2.0"
  
  description = "ABAC-based ACR delete access for non-production artifacts"
}

resource "azurerm_key_vault_certificate" "signingCert" {
  name         = "example"
  key_vault_id = azurerm_key_vault.kv.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      extended_key_usage = ["1.3.6.1.5.5.7.3.3"]

      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject            = "CN=example.com"
      validity_in_months = 12
    }
  }
  
  depends_on = [
    azurerm_role_assignment.kv_certificates_officer,
    azurerm_role_assignment.kv_certificates_user,
    azurerm_role_assignment.kv_crypto_user
  ]
}

# Outputs
output "acr_login_server" {
  description = "The ACR login server URL"
  value       = azurerm_container_registry.acr.login_server
}

output "acr_name" {
  description = "The ACR name"
  value       = azurerm_container_registry.acr.name
}

output "key_vault_name" {
  description = "The Key Vault name"
  value       = azurerm_key_vault.kv.name
}

output "resource_group_name" {
  description = "The resource group name"
  value       = azurerm_resource_group.example.name
}

output "signing_certificate_id" {
  description = "The Key Vault certificate ID for signing"
  value       = azurerm_key_vault_certificate.signingCert.id
}

output "abac_role_assignments" {
  description = "Information about ABAC role assignments"
  value = {
    acr_pull_id   = azurerm_role_assignment.acr_pull.id
    acr_push_id   = azurerm_role_assignment.acr_push.id
    acr_delete_id = azurerm_role_assignment.acr_delete.id
  }
}