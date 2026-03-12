# Sign ACR Container Images with Notary

In this tutorial, you'll learn how to digitally sign a container image hosted in Azure Container Registry using Notary with a Azure Devops. 

Notary is a CNCF project that provides a set of tools that help you sign, store, and verify OCI artifacts using OCI-conformant registries. You'll use Notary's command-line tool, notation, to sign a container image that's pushed to Azure container registry using an Azure DevOps pipeline to automate the process. 

By the end of this tutorial, you'll have a Azure Devops Pipeline that builds a simple Go web app container, pushes the image to ACR, and signs the container image with Notation. 

## Prerequisites

- Azure subscription
- ADO Account
- Terraform. [Install Terraform]( https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- GO. [Install GO in WSL](https://dev.to/deadwin19/how-to-install-golang-on-wslwsl2-2880)

## Get started, use this template

1. Click the `Use this template` button at the top of the page
2. Select an **Owner** and enter a **repository name**, then click `Create repository from template`
3. Use `git clone` to pull the repository to your local development enviornment

## Set up your environment

Before you can begin working on the Azure Devops pipeline there are several Azure resources that need to be deployed first. Follow the below instructions to deploy the required Azure infrastructure using Terraform.


1. Create a service principal

Variables:

export SPN_NAME="<To be defined>"

export SUBS_ID=$(az account show --query id -o tsv)

    ```bash
    az ad sp create-for-rbac --name $SPN_NAME --role contributor \
    --scopes /subscriptions/$SUBS_ID
    ```

    > **TIP**
    > **Store the JSON object in a secure place**. You'll use it to create a credential to authenticate to Azure with the Azure DevOps Pipeline 

> **WARNING**
> This kind of authentication is for demo only purposes and should not be used in production environments.


2. Export Terraform environment variables. You have two ways of doing this:

**Option 1: Manually export each variable**

```bash
export ARM_CLIENT_ID="xxxxxxx-xxxxxx-xxxxxxx-xxxxxxxxx-xxxxxxxx"
export ARM_CLIENT_SECRET="xxxxxxx-xxxxxx-xxxxxxx-xxxxxxxxx-xxxxxxxx"
export ARM_SUBSCRIPTION_ID="xxxxxxx-xxxxxx-xxxxxxx-xxxxxxxxx-xxxxxxxx"
export ARM_TENANT_ID="xxxxxxx-xxxxxx-xxxxxxx-xxxxxxxxx-xxxxxxxx"
export SP_NAME="xxxxxxx-xxxxxx-xxxxxxx-xxxxxxxxx-xxxxxxxx"
```

Replace the `xxxxxxx-xxxxxx-xxxxxxx-xxxxxxxxx-xxxxxxxx` values with the corresponding values of their respective variables

or

**Option 2: Create a `.env` file and source it**

Create a file named `.env` in your project root with the following contents:

```bash
# Azure Subscription
ARM_SUBSCRIPTION_ID="xxxxxxx-xxxxxx-xxxxxxx-xxxxxxxxx-xxxxxxxx"

# Service Principal Credentials
ARM_CLIENT_ID="xxxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxx"             # Also called: applicationId
ARM_CLIENT_SECRET="xxxxxxxxxxxxxxx"  # Never echo or log this

# Optional: Enable Azure CLI backend auth
# ARM_USE_MSI="false"

# Optional: Default Azure Location for Terraform
# ARM_LOCATION="westeurope"
```

Then source the file:

```bash
set +a
source <filename>.env
set -a
```

> **WARNING**
> Add `.env` to your `.gitignore` file to prevent credentials from being committed to version control.

3. Initialize Terraform

    ```bash
    cd terraform
    
    terraform init -upgrade
    ```

4. Apply the Terraform configuration

    ```bash
    terraform apply
    ```

    When prompted type `yes` into the terminal and hit **enter**.

5. Create an Azure Container Registry Token

    ```bash
    az acr token create \
        --name <tokenName> \
        --registry <registryName> \
        --scope-map _repositories_admin \
        --query 'credentials.passwords[0].value' \
        --only-show-errors \
        --output tsv
    ```

    > **TIP**
    > **Store the password value in a secure place**. You'll need it if you later choose to use token-based authentication in your Azure DevOps pipeline.


## Create Azure DevOps Service Connection

To run this pipeline securely in Azure DevOps, create an Azure Resource Manager service connection.

1. Open your Azure DevOps project
2. Go to `Project settings` > `Service connections`
3. Click `New service connection`
4. Select `Azure Resource Manager`
5. Configure the connection and grant access to pipelines
6. Save the service connection name (you'll use it for `azureSubscription` in the pipeline YAML)

## Update the Azure DevOps Pipeline

With the Azure infrastructure deployed and the service connection configured, the last thing you have to do is update the Azure DevOps pipeline file.

1. Open the pipeline file located at `assets/azure-pipeline.yml`.
2. Replace all *placeholder* values from the table below with the appropriate information.
3. Commit and push your changes to the repository.

Placeholder | Description | AzCli command
---------|----------|----------
 `<registry-name>` | Name of the Azure Container Registry | az acr list --query '[].name' -o tsv 
 `your-keyvault-name` | Name of the Azure Key Vault instance | az keyvault list --query '[].name' -o tsv
 `<key-name>` | Name of the signing certificate | az keyvault certificate list --vault-name $vaultName --query '[].name' -o tsv
 `<certificate-key-id>` | Key Id of the Azure Key Vault certificate | az keyvault certificate show --name example --vault-name $vaultName  --query kid -o tsv

Replace `$vaultName` with the name of your Azure Key Vault instance.

## Notation trust store template (self-signed Key Vault cert)

If you want to verify signed images from a workstation or another pipeline using Notation, use the included trust store templates:

- `assets/notation/trustpolicy-selfsigned-akv.template.json`
- `assets/notation/truststore-selfsigned-akv.template.md`

These templates show how to export the certificate from Azure Key Vault, add it to a Notation trust store, and verify a signed image.

## Confirm the container image was signed

Congratulations! You've made it to the end of the tutorial. Your final tasks are to confirm the workflow executed properly and that there is a digital signature attached to the container image hosted on Azure Container Registry.

**View the Azure DevOps pipeline run**

1. To confirm your pipeline executed properly, open your project in Azure DevOps and go to `Pipelines` > `Runs`. You should see a successful run.
2. Open the run details and expand the job steps to review the image build, push, and signing actions.

**Confirm the digital signature exists**

1. Open the Azure portal by going to [portal.azure.com](portal.azure.com)
2. Navigate to your Azure Container Registry instance
3. Under Services, select *Repositories*
4. Select the web-app-sample repository
5. Select the most recent tag
6. Click the **Artifact** tab
7. Confirm cncf.notary.v2.signature exists on the artifact

## Resources

- [setup-notation](https://github.com/Duffney/setup-notation)
- [notary-sign-action](https://github.com/Duffney/notary-sign-action)
- [notation-azure-kv](https://github.com/Azure/notation-azure-kv)
- [Notary Project](https://github.com/notaryproject)# demo-acr-sign-ado
