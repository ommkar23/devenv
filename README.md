# devenv

Portable, GitHub-backed agentic development environment. The primary workflow is a host-native Linux VM accessed through SSH: this repository is `/workspace/devenv`, and project repositories live at `/workspace/<project-name>`. Docker is available for project services and isolated builds, not as the primary interactive development environment.

## Included

- Hermes CLI with `HERMES_HOME=/workspace/devenv/.hermes`
- Git, Git LFS, GitHub CLI, SSH, Python + uv, Node.js, compilers, CMake, Docker + Compose, tmux, jq/yq, and ripgrep
- Non-secret Hermes configuration tracked in Git

## Bootstrap any Ubuntu/Debian VM

The provider-neutral bootstrap is `scripts/bootstrap-host.sh`. It installs the
host-native development toolchain, Docker, GitHub CLI, Hermes, and the
`HERMES_HOME` environment. It does not create cloud infrastructure or install
a cloud-provider CLI.

After cloning this repository at `/workspace/devenv`, run it as `op`:

```bash
ssh op@<VM-IP> 'cd /workspace/devenv && sudo scripts/bootstrap-host.sh'
```

Reconnect after the script completes (Docker group membership applies on the next login). Zed connects directly to the host SSH service:

```bash
zed ssh://op@<VM-IP>:/workspace/devenv
```

The bootstrap persists:

```bash
HERMES_HOME=/workspace/devenv/.hermes
```

Verify with:

```bash
ssh op@<VM-IP> 'which hermes && hermes --version && printf "%s\n" "$HERMES_HOME"'
```

## Hermes authentication

Hermes credentials—including OpenAI Codex OAuth—are stored in the persistent,
Git-ignored `$HERMES_HOME/auth.json`. They survive normal VM stop/start and
reboots because `/workspace/devenv` is on the VM boot disk.

To authenticate with a ChatGPT/Codex subscription from your Mac, use device
authentication so the VM never tries to open a browser:

```bash
ssh -t op@<VM-IP> 'hermes auth add openai-codex --type oauth --no-browser'
```

Complete the displayed browser flow, then run `hermes model` on the VM to
select OpenAI Codex and the preferred model. Other providers can be added with
`hermes auth add <provider>` or selected through `hermes model`. Do not commit
`auth.json`, API keys, or session data.

## Projects

Add one SSH Git URL per line to `projects.txt`, then run:

```bash
DEVENV_SYNC_PROJECTS=1 /workspace/devenv/scripts/bootstrap.sh
```

Projects are intentionally cloned at runtime—not during host bootstrap—so private Git credentials remain outside setup artifacts and project changes do not require rebuilding the environment.

## Azure VM

The Azure provisioner creates one Ubuntu 24.04 VM with a static Standard IPv4
address, CIDR-restricted SSH, a system-assigned managed identity, and an
RBAC-enabled Key Vault. The default `Standard_D2s_v5` size provides 2 vCPU and
8 GiB RAM; `/workspace` lives on a persistent 100 GiB Standard SSD OS disk.

Prerequisites are an authenticated Azure CLI, an SSH public key, a globally
unique Key Vault name, and an IPv4 CIDR for your current client address. The
provisioning identity needs permission to create the resources and role
assignments—normally Contributor plus User Access Administrator, or Owner, at
the resource-group or subscription scope. Uploading secrets separately needs
the `Key Vault Secrets Officer` role on the vault.

Configure and provision from your local machine:

```bash
export SUBSCRIPTION_ID=your-azure-subscription-id
export SSH_CIDR=203.0.113.4/32
export SSH_PUBLIC_KEY_FILE="$HOME/.ssh/id_ed25519.pub"
export KEY_VAULT=example-devenv-vault
export RESOURCE_GROUP=devenv-rg
infrastructure/azure/provision.sh
```

Replace `example-devenv-vault` with a globally unique 3–24 character Key Vault
name before running the provisioner.

Check the current user's vault-scoped writer role and grant it when the first
command returns no assignment (the grant requires role-assignment permission):

```bash
UPLOADER_ID="$(az ad signed-in-user show --query id --output tsv)"
VAULT_ID="$(az keyvault show --subscription "$SUBSCRIPTION_ID" --resource-group "$RESOURCE_GROUP" \
  --name "$KEY_VAULT" --query id --output tsv)"
az role assignment list --subscription "$SUBSCRIPTION_ID" --assignee-object-id "$UPLOADER_ID" \
  --role "Key Vault Secrets Officer" --scope "$VAULT_ID" --output table
az role assignment create --subscription "$SUBSCRIPTION_ID" --assignee-object-id "$UPLOADER_ID" \
  --assignee-principal-type User --role "Key Vault Secrets Officer" --scope "$VAULT_ID"
```

`LOCATION`, `RESOURCE_GROUP`, `VM_NAME`, `VM_SIZE`, `BOOT_DISK_GB`, and the
network resource names are optional overrides. Provisioning is idempotent for
compatible resources and refuses to replace a VM when it detects incompatible
drift.

On a new VM, use the public IP printed by the provisioner to install Git and
clone this public repository before running its Azure bootstrap wrapper. Then
reconnect:

```bash
ssh op@<AZURE-VM-IP> 'sudo apt-get update && sudo apt-get install -y git && sudo install -d -o op -g op /workspace && git clone https://github.com/ommkar23/devenv.git /workspace/devenv'
ssh op@<AZURE-VM-IP> 'cd /workspace/devenv && sudo infrastructure/azure/bootstrap-host.sh'
ssh op@<AZURE-VM-IP>
zed ssh://op@<AZURE-VM-IP>:/workspace/devenv
```

The Azure CLI inside the VM signs in with the system-assigned managed identity;
it does not need a personal login or stored service-principal credential. From
your local machine, upload or rotate a UTF-8 env file as a new Key Vault secret
version:

```bash
infrastructure/azure/put-secret.sh devenv-env /path/to/devenv.env
```

On the VM, download the latest version into a private mode-`600` runtime file:

```bash
ssh op@<AZURE-VM-IP> "AZURE_KEY_VAULT='$KEY_VAULT' /workspace/devenv/scripts/load-azure-secret.sh devenv-env"
# Source the path printed by the command above.
```

Alternatively, set `DEVENV_AZURE_SECRET=devenv-env` and run
`scripts/bootstrap.sh`. Do not set it together with `DEVENV_GCP_SECRET`.

Deallocate—not merely guest-shutdown—the VM to stop compute billing, and start
it again when needed:

```bash
az vm deallocate --subscription "$SUBSCRIPTION_ID" --resource-group devenv-rg --name devenv-01
az vm start --subscription "$SUBSCRIPTION_ID" --resource-group devenv-rg --name devenv-01
```

The managed OS disk uses the `Detach` delete option, so deleting only the VM
keeps the disk and `/workspace` data for manual recovery; the provisioner does
not automatically reattach an orphaned OS disk.

Deleting the resource group also deletes the retained disk. The managed disk, static public IP, and Key Vault can continue to incur costs while the VM is deallocated.

Set `VM_SIZE` before the first provision to choose another size. For an existing
VM, resize explicitly and then use the matching `VM_SIZE` on later provisioner
runs:

```bash
az vm resize --subscription "$SUBSCRIPTION_ID" --resource-group devenv-rg \
  --name devenv-01 --size Standard_D4s_v5
```

## GCP Secret Manager

On the GCP VM, attach a service account with `roles/secretmanager.secretAccessor` only for the specific secret(s) needed. Store an env file as a Secret Manager secret, then on the host run:

```bash
export GCP_PROJECT_ID=your-gcp-project
/workspace/devenv/scripts/load-gcp-secret.sh devenv-env
# Source the path printed by the command above.
```

The secret is written with mode `600` under the user's runtime directory (or a private `/tmp` fallback), never to the Git checkout. Do not commit credentials, OAuth tokens, sessions, or `.env` files.

## GCP host

`infrastructure/gcp/provision.sh` creates the GCE VM, a static IP, a firewall limited to one source CIDR on SSH port `22`, and a VM service account. The GCP wrapper `infrastructure/gcp/bootstrap-host.sh` runs the provider-neutral bootstrap and then installs the Google Cloud CLI for GCP Secret Manager use. Use a repository deploy key—not a personal SSH key—to clone the private repository.

On GCP, use the wrapper instead of the generic command when you need `gcloud`:

```bash
ssh op@<VM-IP> 'cd /workspace/devenv && sudo infrastructure/gcp/bootstrap-host.sh'
```

For an unsupported cloud provider, use `scripts/bootstrap-host.sh` and add only
that provider's CLI/secrets integration in a separate provider wrapper.

Stopping the VM when the environment is idle stops compute billing; stopping individual processes does not.
