# Terraform Configuration for Azure Container Registry with ABAC

This Terraform configuration provisions an Azure Container Registry with Attribute-Based Access Control (ABAC), Key Vault, and signing certificates.

## Prerequisites

1. Azure CLI installed
2. Terraform installed
3. Azure Service Principal with appropriate permissions
4. Configured `template.env` file with your credentials.

## Setup Instructions

### 1. Configure secret.env

Rename the `template.env` file for `secret.env` and upadate with your Azure Service Principal credentials:

```bash
# Azure Active Directory Tenant
ARM_TENANT_ID="your-tenant-id"

# Azure Subscription
ARM_SUBSCRIPTION_ID="your-subscription-id"

# Service Principal Credentials
ARM_CLIENT_ID="your-app-id"
ARM_CLIENT_SECRET="your-client-secret"
```

**Important**: Never commit `secret.env` to version control. Ensure it's in `.gitignore`.

### 2. Load Environment Variables

Before running Terraform commands, load the environment variables:

```bash
# Source the environment variables (option 1)
export $(grep -v '^#' secret.env | xargs)

# Or use set -a to auto-export (option 2)
set -a
source secret.env
set +a
```

### 3. Initialize Terraform

```bash
cd terraform
terraform init
```

### 4. Plan the Deployment

```bash
terraform plan
```

The Terraform variables will automatically pick up the values from the environment variables:
- `ARM_TENANT_ID` → `var.tenant_id`
- `ARM_SUBSCRIPTION_ID` → `var.subscription_id`
- `ARM_CLIENT_ID` → `var.client_id`
- `ARM_CLIENT_SECRET` → `var.client_secret`

### 5. Apply the Configuration

```bash
terraform apply
```

### 6. Access Outputs

After deployment, you can access the outputs:

```bash
terraform output acr_login_server
terraform output acr_name
terraform output key_vault_name
terraform output resource_group_name
```

## ABAC Configuration

This configuration includes fine-grained access control using ABAC:

### Pull Access
- Allowed tags: `latest`, `v*`, `prod-*`

### Push Access
- Allowed repositories: `web-app-sample`, `approved/*`, `prod/*`

### Delete Access
- Allowed tags: `dev-*`, `test-*`
- Allowed repositories: `sandbox/*`

You can customize these in the variables defined in `main.tf`:
- `allowed_pull_tags`
- `allowed_push_repositories`
- `allowed_delete_tags`

## Security Best Practices

1. **Never commit** `secret.env` to version control
2. Set restrictive permissions on `secret.env`:
   ```bash
   chmod 600 secret.env
   ```
3. Rotate Service Principal credentials regularly
4. Use Azure Key Vault for production secrets
5. Consider using Managed Identity instead of Service Principal where possible

## Clean Up

To destroy all resources:

```bash
terraform destroy
```

## Troubleshooting

If you encounter authentication errors:

1. Verify environment variables are loaded:
   ```bash
   echo $ARM_TENANT_ID
   echo $ARM_SUBSCRIPTION_ID
   echo $ARM_CLIENT_ID
   # Don't echo CLIENT_SECRET for security
   ```

2. Verify Service Principal has required permissions:
   - Contributor role on the subscription
   - Ability to create role assignments

3. Check Azure CLI authentication:
   ```bash
   az login --service-principal -u $ARM_CLIENT_ID -p $ARM_CLIENT_SECRET --tenant $ARM_TENANT_ID
   az account show
   ```
