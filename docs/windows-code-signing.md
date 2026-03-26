# Windows Code Signing — Handover Document

**Status:** In progress  
**Goal:** Remove the "Unknown Publisher" / SmartScreen warning for all Resonance IDE Windows installers  
**Assigned to:** _[fill in developer name]_  
**Owner:** Jens Mattke  
**Last updated:** 2026-03-24

---

## Background

All Windows installers built by our CI/CD are currently **unsigned**. When a user downloads and runs `Resonance-Setup.exe`, Windows SmartScreen can block it with _"Windows protected your PC — Unknown publisher"_. This is a major friction point at launch.

The fix is to sign `.exe` and `.msi` files during GitHub Actions.  
Important: this is a **workflow migration** from SignPath to Azure Artifact Signing, not only a secret injection.

---

## Chosen Solution: Azure Artifact Signing

**Why Azure over Sectigo EV or SignPath Foundation:**

| Option | Cost | SmartScreen | CI/CD compatible | Verdict |
|---|---|---|---|---|
| SignPath Foundation | Free | ✅ | ✅ | OSS-only, we are commercial |
| Sectigo EV cert | ~$829/yr + HSM plan | ✅ | ❌ Complex HSM/token integration path | Too complex |
| **Azure Artifact Signing** | ~$9.99/month (plus transaction cost) | ✅ Immediate | ✅ Official GitHub Action | **→ Use this** |

Azure Artifact Signing is Microsoft's managed service. It:
- Stores private keys in Microsoft-managed HSM
- Supports GitHub Actions directly (`azure/artifact-signing-action@v1`)
- Is trusted by Windows ecosystem
- Requires one-time company Identity Validation

---

## Architecture

```
GitHub Actions (stable-windows.yml / insider-windows.yml)
  └── builds .exe + .msi into assets/
  └── azure/login (OIDC preferred)
  └── azure/artifact-signing-action@v1
        └── endpoint (must match resource region)
        └── account + certificate profile
  └── prepare checksums / release / upload
```

---

## What Exists Already

The SignPath signing block in:
- `.github/workflows/stable-windows.yml`
- `.github/workflows/insider-windows.yml`

must be replaced with the Azure signing action. Build, checksum, release, and upload logic can stay.

---

## Prerequisites (Do This First)

### 1) CLI and extension sanity checks

Run these commands before Step 1:

```bash
az --version

# Install the extension that provides Artifact Signing commands.
# One of these is expected to work depending on CLI packaging/version.
az extension add --name trustedsigning || true
az extension add --name artifact-signing || true

# Verify available command groups and pick the one your CLI exposes.
az -h | grep -E "artifact-signing|trustedsigning|codesigning"
```

If `az codesigning ...` is not available on your machine, use the command group that your CLI exposes (`trustedsigning` or `artifact-signing`) with equivalent subcommands.

### 2) Permissions needed in Azure

The operator must be able to create:
- Resource Group
- Artifact Signing Account
- Certificate Profile
- App Registration / Service Principal
- RBAC role assignments

---

## Setup Steps

### Step 1 — Create Azure resources

Use your verified command group (`codesigning`, `trustedsigning`, or `artifact-signing`). Example below keeps `codesigning` naming; adapt if your CLI exposes a different group.

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RESOURCE_GROUP="resonance-signing-rg"
LOCATION="westeurope"
ACCOUNT_NAME="resonance-signing"
PROFILE_NAME="resonance-windows"

az account set --subscription "$SUBSCRIPTION_ID"
az provider register --namespace Microsoft.CodeSigning
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

az codesigning account create \
  --name "$ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Basic

az codesigning certificate-profile create \
  --account-name "$ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --profile-name "$PROFILE_NAME" \
  --profile-type PublicTrust
```

Capture outputs:
- Endpoint URI (for West Europe: `https://weu.codesigning.azure.net/`)
- Account name (`resonance-signing`)
- Certificate profile name (`resonance-windows`)

### Region/endpoint guardrail

The endpoint **must** match the resource region. Mismatch commonly returns 403 during signing.

---

### Step 2 — Submit Identity Validation (portal)

1. Open Azure Portal Artifact Signing account
2. Go to **Identity Validation** → **New validation**
3. Submit legal entity data
4. Upload business proof (e.g. Handelsregisterauszug)
5. Wait for approval (typically days, not minutes)

Signing with public trust profile will not work until this is approved.

---

### Step 3 — Authentication choice for GitHub Actions

## Preferred: OIDC (recommended)

No long-lived client secret required.

1. Create app registration and service principal
2. Add federated credential for GitHub repo/environment
3. Save only:
   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`

## Fallback: client secret

Use only if OIDC cannot be used:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_CLIENT_SECRET`

If using secret-based auth, define secret expiry owner and rotation date at creation time.

---

### Step 4 — Assign signing role

Grant the service principal role on the certificate profile scope:

```bash
ACCOUNT_ID=$(az codesigning account show \
  --name "$ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query id -o tsv)

az role assignment create \
  --assignee "$APP_ID" \
  --role "Artifact Signing Certificate Profile Signer" \
  --scope "$ACCOUNT_ID/certificateProfiles/$PROFILE_NAME"
```

---

### Step 5 — Add GitHub secrets

OIDC path:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

Secret fallback path:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_CLIENT_SECRET`

---

### Step 6 — Update CI workflows

Files:
- `.github/workflows/stable-windows.yml`
- `.github/workflows/insider-windows.yml`

Changes:
1. Remove SignPath env/steps (`SIGNPATH_AVAILABLE`, Upload unsigned artifacts for SignPath, SignPath submit step)
2. Add Azure login + Artifact Signing action
3. Ensure workflow `permissions` include `id-token: write` for OIDC

Example (OIDC recommended):

```yaml
permissions:
  id-token: write
  contents: read

- name: Azure login (OIDC)
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

- name: Sign files with Artifact Signing
  uses: azure/artifact-signing-action@v1
  with:
    endpoint: https://weu.codesigning.azure.net/
    signing-account-name: resonance-signing
    certificate-profile-name: resonance-windows
    files-folder: assets/
    files-folder-filter: exe,msi
    file-digest: SHA256
    timestamp-rfc3161: http://timestamp.acs.microsoft.com
    timestamp-digest: SHA256
  if: env.SHOULD_BUILD == 'yes' && (env.SHOULD_DEPLOY == 'yes' || github.event.inputs.generate_assets == 'true')
```

Fallback (secret auth): keep the same signing step but provide `azure-tenant-id`, `azure-client-id`, `azure-client-secret` directly in `with:`.

---

## Verification (Release Gate)

Run all checks before calling migration complete:

1. CI run succeeds on `stable-windows` with `generate_assets=true`
2. Artifact signature is valid on Windows:

```powershell
Get-AuthenticodeSignature .\Resonance-Setup.exe | Select-Object Status, SignerCertificate
Get-AuthenticodeSignature .\Resonance-Setup.msi | Select-Object Status, SignerCertificate
```

3. Timestamp present and valid
4. Fresh Windows VM install test (no prior trust/reputation artifacts)
5. At least one internal smoke install from downloaded release artifact

---

## Cost (Estimate)

| Item | Estimate |
|---|---|
| Azure Artifact Signing (Basic SKU) | ~$9.99 / month |
| Signing transactions | Variable by volume |
| Identity Validation | Included |
| **Total** | **Volume-dependent; baseline ~monthly SKU** |

---

## Timeline (Estimate)

| Step | Dependency | Expected time |
|---|---|---|
| Azure resource + CI wiring | Azure access + developer availability | Same day |
| Identity validation | Company documents + Microsoft review | Several business days |
| First production signed release | Validation approved + successful CI run | After above |

---

## Open Questions / Blockers

- [ ] Confirm command group naming in target developer environment (`codesigning` vs `trustedsigning` vs `artifact-signing`)
- [ ] Confirm Azure subscription and region of record
- [ ] Decide auth mode: OIDC (recommended) vs client secret fallback
- [ ] Identify owner for identity validation submission and legal documents
- [ ] If client secret is used, document rotation owner/date

---

## References

- [Azure Artifact Signing docs](https://learn.microsoft.com/en-us/azure/artifact-signing/)
- [Signing integrations](https://learn.microsoft.com/en-us/azure/artifact-signing/how-to-signing-integrations)
- [GitHub Action: azure/artifact-signing-action](https://github.com/azure/artifact-signing-action)
- Existing CI workflows: `.github/workflows/stable-windows.yml`, `.github/workflows/insider-windows.yml`
