# Recommended Azure VM design

## Question

What Azure resources, identity model, secret flow, storage behavior, and idempotent CLI patterns should the first `devenv` Azure VM implementation use?

## Summary

Use one ordinary Ubuntu VM in a dedicated resource group, with explicit networking, a system-assigned managed identity, and one Key Vault for this development environment.

Recommended configurable defaults:

| Setting | Default | Rationale |
| --- | --- | --- |
| Resource group | `devenv-rg` | Lifecycle boundary for all Azure resources |
| Location | `centralindia` | Close to the user; override through `LOCATION` |
| VM name | `devenv-01` | Matches the GCP host convention |
| VM size | `Standard_D2s_v5` | Starter 2-vCPU/8-GiB general-purpose VM for Codex, Hermes, and light Docker use; keep `VM_SIZE` configurable |
| Image | `Canonical:ubuntu-24_04-lts:server:latest` | Ubuntu 24.04 x64 Gen2; verified active in Central India on 2026-08-09 |
| OS disk | 100 GiB `StandardSSD_LRS` | Cost-conscious persistent starter disk; make size and SKU configurable |
| Admin user | `op` | Matches the neutral bootstrap |
| Public IP | Standard IPv4 | Standard SKU uses static allocation |
| SSH ingress | TCP 22 from one required `SSH_CIDR` | No internet-wide SSH rule |

### Provisioning layout

Create explicit named resources in dependency order:

1. Resource group.
2. Virtual network and subnet.
3. Network security group and one `AllowSSHFromCIDR` inbound rule.
4. Standard static IPv4 public IP.
5. NIC connected to the subnet, NSG, and public IP.
6. Ubuntu VM using the NIC, SSH public-key authentication, system-assigned identity, Trusted Launch, and the managed OS disk.
7. Key Vault using Azure RBAC.
8. `Key Vault Secrets User` role assignment for the VM identity at vault scope.

The NSG command must set source CIDR, destination port `22`, protocol `Tcp`, direction `Inbound`, access `Allow`, and a unique priority explicitly. Azure CLI's NSG rule defaults include source `*` and destination port `80`, so relying on defaults would be unsafe and incorrect.

Require `SSH_PUBLIC_KEY_FILE` to exist and `SSH_CIDR` to be a single IPv4 CIDR, as the GCP script does. Use `--authentication-type ssh` and `--ssh-key-values`; do not enable password authentication. A public IP is appropriate for the current Zed/SSH workflow, while Azure Bastion or private VPN access can be a later hardening option.

### Identity and secrets

Use a system-assigned managed identity (`--assign-identity`). It has no credential for the repository to store and can authenticate inside the VM with `az login --identity`.

Use one Key Vault per application/environment, following Microsoft's recommendation. Because vault names are globally unique and soft-deleted names cannot immediately be reused, make `KEY_VAULT` an explicit required input rather than guessing a globally unique name.

Grant the VM only the built-in `Key Vault Secrets User` role at the vault scope. In scripts, use its stable role ID `4633458b-17de-408a-b874-0445c86b69e6`, which Microsoft recommends over a role name. The human or automation running `put-secret.sh` separately needs permission to set secrets, normally `Key Vault Secrets Officer`.

`put-secret.sh` should upload or rotate the entire env file with:

```text
az keyvault secret set --vault-name ... --name ... --file ... --encoding utf-8
```

This command creates the secret or a new version. `load-azure-secret.sh` should authenticate with the VM identity and use `az keyvault secret download --encoding utf-8 --overwrite` into the same private runtime-directory pattern as the GCP loader, followed by an explicit `chmod 600`. Never echo secret contents. Key Vault secrets are limited to 25 KB, which is ample for the current env file but should be validated before upload.

### Storage and lifecycle

Keep `/workspace` on the OS disk for parity with GCP and to avoid first-boot formatting/mounting complexity. Reboots, stops, and deallocation preserve it. Explicitly set the OS disk delete option to `Detach`, even though CLI-created VMs currently default to detach, so deleting only the VM resource does not silently delete the workspace disk. Deleting the entire resource group still deletes the disk.

Use `az vm deallocate`, not guest shutdown or a simple power-off, to stop compute billing. Azure documents `Stopped (Allocated)` as billed and `Deallocated` as not billed; managed disks and networking can still incur charges.

A separate `/workspace` data disk is a reasonable future enhancement if VM replacement becomes routine. It is not necessary for initial provider parity.

### Idempotent shell behavior

Follow these rules rather than assuming every Azure `create` command is idempotent:

- Resolve or require a subscription ID and pass `--subscription` consistently; show the selected subscription before mutation.
- Use `az group create` for the resource group, and `show`/`exists` before other creates.
- On every run, update the mutable SSH NSG rule to the requested CIDR.
- If a named public IP, VNet, subnet, NIC, vault, or VM already exists, validate its critical properties. Fail clearly on incompatible drift instead of silently replacing it.
- If the VM exists, ensure its system identity is enabled, but do not automatically resize it, replace its image, or shrink its disk. Those are explicit lifecycle operations.
- Query the VM principal ID after creation. Check for the vault role assignment before creating it, and retry briefly for Microsoft Entra/RBAC propagation.
- Treat a larger requested disk size as a separate supported expansion path; Azure can expand managed disks but cannot shrink them.
- Finish by printing VM name, power state, size, private/public IP, identity principal ID, disk size/SKU, and vault name without printing secret values.

## Sources

- [Create a Linux VM with Azure CLI](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-cli)
- [Find Azure Marketplace images with Azure CLI](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/cli-ps-findimage)
- [Install Azure CLI on Linux](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux)
- [Configure managed identities on Azure VMs](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/how-to-configure-managed-identities)
- [Sign in to Azure CLI with a managed identity](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli-managed-identity?view=azure-cli-latest)
- [Azure Key Vault RBAC guide](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)
- [Azure CLI Key Vault secret reference](https://learn.microsoft.com/en-us/cli/azure/keyvault/secret?view=azure-cli-latest)
- [About Key Vault secrets](https://learn.microsoft.com/en-us/azure/key-vault/secrets/about-secrets)
- [Key Vault soft-delete behavior](https://learn.microsoft.com/en-us/azure/key-vault/general/soft-delete-overview)
- [Azure CLI NSG rule reference](https://learn.microsoft.com/en-us/cli/azure/network/nsg/rule?view=azure-cli-latest)
- [Create a Standard public IP with Azure CLI](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/create-public-ip-cli)
- [Azure public IP allocation and SKUs](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/public-ip-addresses)
- [Azure managed disk types](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-types)
- [Expand a Linux VM disk](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/expand-disks)
- [VM and attached-resource delete options](https://learn.microsoft.com/en-us/azure/virtual-machines/delete)
- [Azure VM states and billing](https://learn.microsoft.com/en-us/azure/virtual-machines/states-billing)
- [Trusted Launch for Azure VMs](https://learn.microsoft.com/en-us/azure/virtual-machines/trusted-launch)

## Implications

- The first implementation remains shell-only and mirrors the GCP file layout.
- `Standard_D2s_v5` is a starter, not a promise of regional quota or availability. The provisioner should produce a clear Azure error and allow `VM_SIZE` override.
- Trusted Launch is already the default for new compatible Gen2 VMs, but setting it explicitly documents the security posture. The selected Ubuntu image is Gen2 and reports Trusted Launch support.
- `StandardSSD_LRS` prioritizes cost. Users doing heavier Docker builds can override to `Premium_LRS` without changing the architecture.
- A dedicated vault plus vault-scope reader role is simpler and aligns better with Microsoft guidance than per-secret role assignments.

## Risks

- Role assignments can take several minutes to propagate. Immediate secret download may transiently fail and needs a bounded retry or a clear retry message.
- The provisioning caller needs permission to create role assignments. `Contributor` alone is not sufficient; `Owner`, `User Access Administrator`, or an appropriately scoped role is required.
- A public SSH endpoint remains exposed to scanning even with CIDR restriction. A changing client IP requires rerunning provisioning to update the NSG rule.
- Standard public IPs, disks, and Key Vault can continue to cost money while the VM is deallocated.
- `latest` gives current Ubuntu security updates on new VMs but makes recreation non-bit-for-bit reproducible. Record the resolved image version in provision output; pinning can be added if exact recreation becomes important.
- OS-disk-only persistence couples workstation data to the VM resource group. Resource-group deletion bypasses the protection offered by disk `Detach` on VM deletion.
- Key Vault public network access with RBAC is the simplest initial design. Private endpoints or vault network ACLs would reduce network exposure but add DNS, subnet, and local upload complexity and should be a separate hardening milestone.
