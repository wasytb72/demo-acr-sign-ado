# Notation trust store template (Azure Key Vault self-signed)

Use this template when an image is signed with a self-signed certificate stored in Azure Key Vault via the `azureKeyVault` Notation plugin.

**Only if you do not want to include the verify step in your ADO Pipeline**

**This is a manually check process**

## 1) Export signer certificate from Key Vault

```bash
# Required values
KV_NAME="<key-vault-name>"
CERT_NAME="<certificate-name>"

# Export certificate in PEM (public cert only)
az keyvault certificate download \
  --vault-name "$KV_NAME" \
  --name "$CERT_NAME" \
  --encoding PEM \
  --file ./akv-selfsigned-signer.pem
```

## 2) Add cert to local Notation trust store

```bash
# Create the trust store entry referenced by trustpolicy-selfsigned-akv.template.json
notation cert add \
  --type signingAuthority \
  --store akv-selfsigned-store \
  ./akv-selfsigned-signer.pem
```

## 3) Json taxonomy
```json
{
    "version": "1.0",
    "trustPolicies": [
        {
            // Policy for all artifacts, from any registry location.
            "name": "wabbit-networks-images",   // Name of the policy.
            "registryScopes": [ "*" ],          // The registry artifacts to which the policy applies.
            "signatureVerification": {          // The level of verification - strict, permissive, audit, skip.
              "level" : "audit" 
            },
            "trustStores": ["ca:acme-rockets"], // The trust stores that contains the X.509 trusted roots.
            "trustedIdentities": [              // Identities that are trusted to sign the artifact.
              "x509.subject: C=US, ST=WA, L=Seattle, O=acme-rockets.io, OU=Finance, CN=SecureBuilder"
            ]
        }
    ]
}
```
## 3) Install trust policy

```bash
# Linux/macOS
mkdir -p ~/.config/notation
cp assets/notation/trustpolicy-selfsigned-akv.template.json ~/.config/notation/trustpolicy.json

# Windows PowerShell
# New-Item -ItemType Directory -Force "$HOME/.config/notation" | Out-Null
# Copy-Item "assets/notation/trustpolicy-selfsigned-akv.template.json" "$HOME/.config/notation/trustpolicy.json" -Force
```

Then edit placeholders in `trustpolicy.json`:
- `<registry-name>`
- `<namespace>`
- `<repository-name>`
- `x509.subject` values (`C`, `ST`, `O`, `CN`) to match your signer certificate subject

If you want to trust any signer identity that chains to the configured trust store, you can set:

```json
"trustedIdentities": ["*"]
```

## 4) Verify a signed image

```bash
notation verify <registry-name>.azurecr.io/<repository-name>:<tag>
```

## Notes
- For production, replace `"trustedIdentities": ["*"]` with explicit signer identities.
- If verification fails, confirm the cert in Key Vault matches the cert/key used by signing and that the image reference matches `registryScopes`.
