# Sign ACR Container Images with Notary

In this tutorial, you'll learn how to digitally sign a container image hosted in Azure Container Registry using Notary with a GitHub workflow. 

Notary is a CNCF project that provides a set of tools that help you sign, store, and verify OCI artifacts using OCI-conformant registries. You'll use Notary's command-line tool, notation, to sign a container image that's pushed to Azure container registry using several GitHub Actions to automate the process. 

By the end of this tutorial, you'll have a GitHub workflow that builds a simple Go web app container, pushes the image to ACR, and signs the container image with Notation. 

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

Before you can begin working on the GitHub workflow there are several Azure resources that need to be deployed first. Follow the below instructions to deploy the required Azure infrastructure using Terraform.

1. Create a service principal

Variables:

export SPN_NAME="<To be defined>"
export SUBS_ID=$(az account show --query id)

    ```bash
    az ad sp create-for-rbac --name $SPN_NAME --role contributor \
    --scopes /subscriptions/$SUBS_ID
    ```

    > **TIP**
    > **Store the JSON object in a secure place**. You'll use it to create a credential to authenticate to Azure with the Azure Login GitHub Action.
    
    > **NOTE**
    > The credential lifetime will be set automatically according to your Azure tenant's policy (typically 90-180 days for restricted environments). The credential will need to be rotated when it expires.

2. Export Terraform environment variables

    ```bash
    export ARM_CLIENT_ID="00000000-0000-0000-0000-000000000000"
    export ARM_CLIENT_SECRET="00000000-0000-0000-0000-000000000000"
    export ARM_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
    export ARM_TENANT_ID="00000000-0000-0000-0000-000000000000"
    export SP_NAME="00000000-0000-0000-0000-000000000000"
    ``` 

    Replace the `00000000` values with your service principal information.

3. Initialize Terraform

    ```bash
    cd terraform
    
    terraform init
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
    > **Store the password value in a secure place**. You'll need to store it as a GitHub secret later in the demo.

    **Store the password value in a secure place**. You'll need to store it as a Azure Devops Variable later in the demo.


## Create GitHub Action Secrets

To improve the security of your GitHub workflow, you'll create several GitHub Action Secrets to securely pass the credentials to your workflow.

1. Click the `Settings` on the repository
2. Select `Secrets`, then `Actions`, 
3. Then click `New repository secret`
3. Enter the secret name and value
5. Click **Add secret**

Repeat steps 3-5 for each secrets listed below.

Name | Value | 
---------|----------|
 AZURE_CREDENTIALS | JSON object of the Azure Service Principal output from the `az ad sp create-for-rbac` command | 
 NOTATION_USERNAME | Name of the Azure Container Registry token | 
 NOTATION_PASSWORD | Password of the Azure Container Registry token | 

> **TIP**
> In case you didn't save the JSON output, rerunning the `az ad sp create-for-rbac` command will reset the password of the service principal and generate a new JSON object.

## Update the GitHub Workflow

With the Azure infrastructure deployed and your GitHub Actions secrets configured, the last thing you have to do is update the GitHub workflow file.

1. Open the GitHub workflow file located at `.github/workflows/docker-image.yml`.
2. Replace all *placeholder* values from the table below with the appropriate information.
3. Issue the `git add`, `git commit`, and `git push` commands to push your changes to GitHub.

Placeholder | Description | AzCli command
---------|----------|----------
 `<registry-name>` | Name of the Azure Container Registry | az acr list --query '[].name' -o tsv 
 `<key-name>` | Name of the signing certificate | az keyvault certificate list --vault-name $vaultName --query '[].name' -o tsv
 `<certificate-key-id>` | Key Id of the Azure Key Vault certificate | az keyvault certificate show --name example --vault-name $vaultName  --query kid -o tsv

Replace `$vaultName` with the name of your Azure Key Vault instance.

## Confirm the container image was signed

Congratulations! You've made it to the end of the tutorial. Your final tasks are to confirm the workflow executed properly and that there is a digital signature attached to the container image hosted on Azure Container Registry.

**View the GitHub workflow run**

1. To confirm your workflow executed properly, **open the repository** on GitHub and click the **Actions** tab. You should see a workflow run that is green.
2. Click to expand the steps within the workflow and examine the actions taken to sign the container image.

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
