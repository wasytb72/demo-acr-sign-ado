terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.1.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.28.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4.3"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.0"
    }
  }
}

provider "azurerm" {
  features {}
  
  # Authentication is automatically configured via environment variables:
  # ARM_TENANT_ID, ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET
  # Load them from secret.env using: set -a && source secret.env && set +a
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
  
  # Allow public access from all networks
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  
  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      tags
    ]
  }
}

# Key Vault Certificates Officer - Full certificate management permissions
resource "azurerm_role_assignment" "kv_certificates_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azuread_client_config.current.object_id
  
  description = "Grants service principal full certificate management permissions"
}

# Key Vault Certificates User - Read certificate permissions
resource "azurerm_role_assignment" "kv_certificate_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Certificate User"
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

# Wait for RBAC role assignments to propagate (can take up to 5 minutes)
resource "time_sleep" "wait_for_rbac" {
  depends_on = [
    azurerm_role_assignment.kv_certificates_officer,
    azurerm_role_assignment.kv_certificate_user,
    azurerm_role_assignment.kv_crypto_user
  ]
  
  create_duration = "60s"
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

# ACR Pull role assignment
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = data.azuread_client_config.current.object_id
  
  description = "ACR pull access for container images"
}

# ACR Push role assignment
resource "azurerm_role_assignment" "acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = data.azuread_client_config.current.object_id
  
  description = "ACR push access for container images"
}

# ACR Delete role assignment (for cleanup operations)
resource "azurerm_role_assignment" "acr_delete" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrDelete"
  principal_id         = data.azuread_client_config.current.object_id
  
  description = "ACR delete access for artifact cleanup"
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
        "digitalSignature",
      ]

      subject            = "CN=example.com"
      validity_in_months = 12
    }
  }
  
  depends_on = [
    time_sleep.wait_for_rbac
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