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


1. Create a service principal.

Variables:

export SPN_NAME="\<SPN NAME\>"

export SUBS_ID=$(az account show --query id -o tsv)

    ```bash
    az ad sp create-for-rbac --name $SPN_NAME --role owner \
        --scopes /subscriptions/$SUBS_ID
    ```

    > **TIP**
    > **Store the JSON object in a secure place**. You'll use it to create a credential to authenticate to Azure with the Azure DevOps Pipeline 

> **WARNING**
> This kind of authentication is for demo only purposes and should not be used in production environments.


1. Export Terraform environment variables. You have two ways of doing this:

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

## Create Azure DevOps Service Connection

To run this pipeline you need two service connections:

Create an Azure Resource Manager service connections under the Service Principal created earlier:

1. Open your Azure DevOps project
2. Go to `Project settings` > `Service connections`
3. Click `New service connection`
4. Select `Azure Resource Manager`
5. Configure the connection and grant access to pipelines
6. Save the service connection name (you'll use it for `azurekvServiceConnection` in the pipeline YAML)

Create an Docker Registry service connection.

1. Open your Azure DevOps project
2. Go to `Project settings` > `Service connections`
3. Click `New service connection`
4. Select `Docker Service Connection`
5. Configure the connection and grant access to pipelines
6. Save the service connection name (you'll use it for `containerRegistry` in the pipeline YAML)

## Update the Azure DevOps Pipeline

With the Azure infrastructure deployed and the service connections configured, the last thing you have to do is update the Azure DevOps pipeline file.

1. Open the pipeline file located at `./assets/azure-pipeline.yml`.
2. Replace all *placeholder* values from the table below with the appropriate information.
3. Create Pipeline with the yaml file indicated on the step 1

Placeholder | Description |
---------|----------|
 `<your-container-registry-service-connection>` |Name of the Docker Registry Service Connection
 `<name-of-your-repository>` | Name of the Azure Container Registry
 `<name-of-your-Azure-Resource-Manager-service-connection>` | Name of the Resource Manager Connection
 `'https://<certficate-name>.vault.azure.net/keys/<key-name>/<key-version>'` | Fill out with the  name and key version of the certificate hosted in Key Vault



## Notation trust store template (self-signed Key Vault cert)

If you want to verify signed images from a workstation or another pipeline using Notation, use the included trust store template:

- `./assets/notation/trustpolicy-selfsigned-akv.template.json`
- Manually verification instructions: `./assets/notation/truststore-selfsigned-akv.template.md`

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
