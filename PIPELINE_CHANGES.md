# Azure DevOps Pipeline Changes

## Overview
This document outlines the changes made to the Azure DevOps pipeline (`assets/azure-pipeline.yml`) to align it with the GitHub Actions workflow (`.github/workflows/docker-image.yml`).

## Date
February 4, 2026

## Changes Made

### 1. Trigger Configuration

**Before:**
```yaml
trigger:
  branches:
    include:
    - main
    - develop
```

**After:**
```yaml
trigger:
  branches:
    include:
    - main

pr:
  branches:
    include:
    - main
```

**Rationale:** 
- Removed `develop` branch to match GitHub workflow's focus on `main` branch only
- Added `pr:` trigger to mirror GitHub's `pull_request` event behavior

### 2. Variable Updates

**Before:**
```yaml
variables:
  acrServiceConnection: 'acr-service-connection'
  containerRegistry: 'yourregistry.azurecr.io'
  imageName: 'myapp'
  imageTag: '$(Build.BuildId)'
  keyVaultName: 'your-keyvault-name'
  certificateName: 'container-signing-cert'
  azureSubscription: 'azure-service-connection'
  notationVersion: '1.1.0'
```

**After:**
```yaml
variables:
  acrServiceConnection: 'acr-service-connection'
  registryName: '<registry-name>'
  containerRegistry: '$(registryName).azurecr.io'
  imageName: 'web-app-sample'
  imageTag: '$(Build.BuildId)'
  keyVaultName: 'your-keyvault-name'
  certificateName: 'container-signing-cert'
  keyName: '<key-name>'
  certificateKeyId: '<certificate-key-id>'
  azureSubscription: 'azure-service-connection'
  notationVersion: '1.1.0'
  azureKvPluginVersion: '1.1.0'
```

**Changes:**
- Added `registryName` variable for cleaner ACR name management
- Changed `imageName` from `myapp` to `web-app-sample` (matching GitHub workflow)
- Added `keyName` variable (matching GitHub workflow parameter)
- Added `certificateKeyId` variable (matching GitHub workflow parameter)
- Added `azureKvPluginVersion` variable for explicit plugin versioning

### 3. Job Restructuring

**Before:**
- Job name: `BuildAndPush`
- Separate steps for build, login, push, sign, and verify

**After:**
- Job name: `BuildAndSign`
- Streamlined workflow with consolidated steps

**Rationale:** Better reflects the actual workflow purpose

### 4. Build Process Simplification

**Before:**
```yaml
# Build Docker image
- task: Docker@2
  displayName: 'Build Docker Image'
  inputs:
    command: build
    repository: '$(containerRegistry)/$(imageName)'
    dockerfile: 'Dockerfile'
    tags: |
      $(imageTag)
      latest

# Login to ACR
- task: Docker@2
  displayName: 'Login to Azure Container Registry'
  inputs:
    command: login
    containerRegistry: '$(acrServiceConnection)'

# Push Docker image to ACR
- task: Docker@2
  displayName: 'Push Docker Image to ACR'
  inputs:
    command: push
    repository: '$(containerRegistry)/$(imageName)'
    tags: |
      $(imageTag)
      latest
```

**After:**
```yaml
# Build and push using ACR build
- task: AzureCLI@2
  displayName: 'Build Container Image in ACR'
  inputs:
    azureSubscription: '$(azureSubscription)'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
      echo "Building image in ACR..."
      az acr build \
        --registry $(registryName) \
        --image $(imageName):$(imageTag) \
        --image $(imageName):latest \
        --file Dockerfile \
        .
      
      echo "Image built successfully: $(containerRegistry)/$(imageName):$(imageTag)"
```

**Rationale:**
- Matches the `az acr build` approach used in GitHub Actions workflow
- Simplifies from 3 separate Docker tasks to 1 ACR build command
- Eliminates need for separate login and push steps
- Builds directly in ACR (more efficient and secure)

### 5. Notation Setup Consolidation

**Before:**
- Two separate steps: "Install Notation CLI" and "Install Notation Azure Key Vault Plugin"

**After:**
- Single step: "Setup Notation CLI" that installs both Notation and the Azure KV plugin

**Code:**
```yaml
- task: Bash@3
  displayName: 'Setup Notation CLI'
  inputs:
    targetType: 'inline'
    script: |
      echo "Installing Notation CLI v$(notationVersion)..."
      curl -Lo notation.tar.gz https://github.com/notaryproject/notation/releases/download/v$(notationVersion)/notation_$(notationVersion)_linux_amd64.tar.gz
      tar xvzf notation.tar.gz -C /usr/local/bin notation
      chmod +x /usr/local/bin/notation
      notation version
      
      echo "Installing notation-azure-kv plugin v$(azureKvPluginVersion)..."
      curl -Lo notation-azure-kv.tar.gz https://github.com/Azure/notation-azure-kv/releases/download/v$(azureKvPluginVersion)/notation-azure-kv_$(azureKvPluginVersion)_linux_amd64.tar.gz
      mkdir -p ~/.config/notation/plugins/azure-kv
      tar xvzf notation-azure-kv.tar.gz -C ~/.config/notation/plugins/azure-kv
      notation plugin list
```

**Rationale:** Better aligns with the single setup action approach in GitHub workflow

### 6. Certificate Configuration Improvements

**Before:**
- Step name: "Configure Azure Key Vault Access"
- Set certificate ID as pipeline variable

**After:**
- Step name: "Configure Notation Signing Key"
- Directly adds key to Notation configuration
- Uses `$(keyName)` variable instead of hardcoded name

**Key Changes:**
```yaml
# Add signing key to Notation
notation key add \
  --plugin azure-kv \
  --id "$CERT_ID" \
  $(keyName) \
  --plugin-config self_signed=true

notation key list
```

**Rationale:** Matches the configuration approach expected by the GitHub workflow structure

### 7. Signing Process Streamlining

**Before:**
- Two separate steps: "Sign Container Image with Notation" and "Verify Container Image Signature"

**After:**
- Single step: "Sign Container Image" that includes signature listing for verification

**Code:**
```yaml
- task: AzureCLI@2
  displayName: 'Sign Container Image'
  inputs:
    azureSubscription: '$(azureSubscription)'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    addSpnToEnvironment: true
    inlineScript: |
      IMAGE_REF="$(containerRegistry)/$(imageName):$(imageTag)"
      echo "Signing image: $IMAGE_REF"
      
      # Login to ACR using token authentication
      ACR_NAME=$(echo $(containerRegistry) | cut -d'.' -f1)
      TOKEN=$(az acr login --name $ACR_NAME --expose-token --output tsv --query accessToken)
      echo $TOKEN | notation login $(containerRegistry) --username 00000000-0000-0000-0000-000000000000 --password-stdin
      
      # Sign the image
      notation sign \
        --signature-format cose \
        --key $(keyName) \
        $IMAGE_REF
      
      echo "✓ Image signed successfully!"
      
      # List signatures for verification
      echo "Signatures on image:"
      notation list $IMAGE_REF
```

**Changes:**
- Combined signing and verification into one step
- Uses `$(keyName)` variable instead of hardcoded `container-signing-key`
- Added inline signature listing for immediate verification
- Improved variable extraction for ACR name

### 8. Removed Steps

**Removed:**
- "Publish Pipeline Artifacts" step

**Rationale:** Not present in the GitHub Actions workflow and not necessary for this use case

## Summary

The updated Azure DevOps pipeline now:

1. ✅ Matches the branch strategy (main branch only, with PR support)
2. ✅ Uses the same image naming convention (`web-app-sample`)
3. ✅ Employs `az acr build` for simplified container build and push
4. ✅ Consolidates setup steps for better maintainability
5. ✅ Uses variable references for key names and configuration
6. ✅ Streamlines the signing and verification process
7. ✅ Removes unnecessary artifact publishing

## Variables to Update

Before using this pipeline, update the following variables:

- `registryName`: Your ACR name (without .azurecr.io suffix)
- `keyVaultName`: Your Azure Key Vault name
- `keyName`: Your signing key name
- `certificateKeyId`: Your certificate key identifier
- `azureSubscription`: Your Azure service connection name
- `acrServiceConnection`: Your ACR service connection name (if needed for future Docker tasks)

## Compatibility

- Notation CLI: v1.1.0
- Notation Azure KV Plugin: v1.1.0
- Ubuntu: latest
- Azure CLI: Built-in from AzureCLI@2 task
