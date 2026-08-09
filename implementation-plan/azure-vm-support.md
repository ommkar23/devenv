# Azure VM support implementation plan

## Goal

Add first-class Azure VM support to `devenv` without changing its host-native Linux architecture or coupling Azure behavior into the provider-neutral bootstrap. The result will provision one secure, persistent Ubuntu development VM, install the Azure CLI through an Azure-specific wrapper, and support loading an env-file secret from Azure Key Vault using the VM's managed identity.

This plan is limited to the `devenv` repository. It will not create or modify live Azure resources during implementation or verification.

## Workflow state

- Phase: `done`
- Research folder: `research/20260809-azure-vm-support/`
- Implementation plan: `implementation-plan/azure-vm-support.md`
- Research subagent: `/root/azure_vm_research` (research complete)
- Implementation agents: `/root/azure_red`, `/root/azure_green`, and `/root/azure_refactor`
- Milestones: Milestones 1-3 complete
- Latest approval: on 2026-08-09, the user approved the Test Plan and asked to proceed
- Verification: provisioning, secret integration, documentation, Bash syntax, and whitespace checks pass without live Azure mutations
- Final review: all actionable correctness, security, documentation, and test-coverage findings resolved; no blocking findings remain

## Confirmed product choices

- Use a configurable `Standard_D2s_v5` default: 2 vCPU and 8 GiB RAM.
- Use Ubuntu 24.04 Gen2 with Trusted Launch.
- Keep `/workspace` on a persistent, configurable 100 GiB Standard SSD OS disk for the first version.
- Expose SSH through a static Standard IPv4 address, restricted to one required IPv4 CIDR.
- Use a system-assigned managed identity instead of stored Azure credentials.
- Use a dedicated, explicitly named Azure Key Vault with Azure RBAC.
- Retain all current GCP behavior unchanged.

## Research basis

- [Azure VM design](../research/20260809-azure-vm-support/azure-vm-design.md) records the recommended Azure resources, VM image and size, security model, disk lifecycle, Key Vault flow, idempotency rules, and Microsoft documentation consulted.
- [Existing repository conventions](../research/20260809-azure-vm-support/existing-repository-conventions.md) records the current provider boundary and the Azure file layout that fits it.

## Public configuration interface

The Azure provisioner will accept environment variables so the default host can be resized or relocated without editing the script:

| Variable | Default or requirement | Purpose |
| --- | --- | --- |
| `SUBSCRIPTION_ID` | Current `az` subscription | Explicit Azure target; every resource command uses it |
| `LOCATION` | `centralindia` | Resource-group and resource location |
| `RESOURCE_GROUP` | `devenv-rg` | Lifecycle boundary for the environment |
| `VM_NAME` | `devenv-01` | VM resource name |
| `VM_SIZE` | `Standard_D2s_v5` | Configurable 2-vCPU starter size |
| `ADMIN_USER` | `op` | SSH user expected by the host bootstrap |
| `BOOT_DISK_GB` | `100` | Persistent OS disk capacity |
| `BOOT_DISK_SKU` | `StandardSSD_LRS` | Managed OS disk tier |
| `SSH_CIDR` | Required | Only IPv4 CIDR allowed to reach TCP 22 |
| `SSH_PUBLIC_KEY_FILE` | `$HOME/.ssh/id_rsa.pub` | Public key installed on the VM |
| `KEY_VAULT` | Required | Globally unique Key Vault name |

Resource names for the VNet, subnet, NSG, public IP, and NIC will have deterministic `devenv-*` defaults and optional environment-variable overrides. `AZURE_KEY_VAULT` and `DEVENV_AZURE_SECRET` will be the runtime inputs used to load a Key Vault secret on the VM.

## Milestone 1: Idempotent Azure infrastructure provisioning

Create `infrastructure/azure/provision.sh` as a strict Bash script parallel to the GCP provisioner.

The script will:

1. Validate Azure CLI authentication, the selected subscription, the SSH public key, the required single IPv4 `SSH_CIDR`, the Key Vault name, and numeric disk size before making changes.
2. Create or validate a dedicated resource group, VNet, subnet, NSG, static Standard IPv4 public IP, and NIC using deterministic names.
3. Create or update the SSH NSG rule with every run so its source is exactly `SSH_CIDR`, protocol is TCP, and destination port is 22.
4. Create the VM only when absent, using `Canonical:ubuntu-24_04-lts:server:latest`, `Standard_D2s_v5` by default, SSH-key authentication, Trusted Launch, a system-assigned identity, and the configured managed OS disk.
5. Set the OS disk delete option to `Detach` so deleting only the VM does not delete the workspace disk.
6. Create or validate an RBAC-enabled Key Vault and grant the VM identity the stable built-in `Key Vault Secrets User` role at vault scope.
7. Tolerate identity and RBAC propagation with bounded retries, while returning a clear failure if access cannot be established.
8. Print a secret-free summary containing subscription, resource group, VM state, size, IPs, identity ID, disk configuration, resolved image version, and vault name.

Existing resources will be inspected rather than replaced. Mutable SSH CIDR and missing identity/role assignment will be reconciled. Incompatible location, network attachment, VM size, image/security mode, or disk drift will fail with a precise message; the provisioner will not resize, replace, or shrink a VM implicitly.

Acceptance criteria:

- A first run expresses the complete Azure resource graph needed by one `devenv` host.
- A second run makes no duplicate resources and safely reconciles the SSH rule, identity, and vault access.
- Invalid or unsafe inputs fail before mutation.
- No secret value, private key, token, or generated environment file enters the repository or command output.

## Milestone 2: Azure host bootstrap and Key Vault secret flow

Create `infrastructure/azure/bootstrap-host.sh` as a thin wrapper around `scripts/bootstrap-host.sh`. It will reuse all existing workstation installation logic, then install Azure CLI from Microsoft's Ubuntu package repository only when needed and print the installed CLI version.

Create `infrastructure/azure/put-secret.sh` to upload or rotate one UTF-8 env file as a Key Vault secret. It will validate the secret name and input file, enforce Key Vault's 25 KB secret limit before upload, use `az keyvault secret set --file`, and never echo contents. The caller must already have a data-plane role such as `Key Vault Secrets Officer`; the script will report that prerequisite clearly rather than granting the human caller broader access.

Create `scripts/load-azure-secret.sh` to run on the VM. It will validate inputs, authenticate with `az login --identity`, download the latest secret version into the same private runtime-directory pattern used by the GCP loader, enforce mode `600`, and print only the safe path/source instruction.

Update `scripts/bootstrap.sh` so `DEVENV_AZURE_SECRET` opts into the Azure loader. If both `DEVENV_GCP_SECRET` and `DEVENV_AZURE_SECRET` are set, it will fail clearly instead of selecting or loading two providers implicitly.

Acceptance criteria:

- The Azure wrapper retains the provider-neutral bootstrap as the single source of truth.
- A VM can access its vault without an interactive user login or stored service-principal secret.
- Secret rotation creates a new Key Vault version, and loading retrieves the latest version into a private runtime file.
- Existing GCP secret loading behaves exactly as before when Azure variables are unset.

## Milestone 3: Configuration examples and operator documentation

Update `.env.example` with safe Azure placeholders and no real credentials.

Update `README.md` with concise Azure instructions covering:

- prerequisites and required Azure permissions, including the separate provisioning and Key Vault writer roles;
- configuration and provisioner invocation;
- Azure-specific host bootstrap;
- SSH and Zed connection commands;
- Key Vault upload and managed-identity load commands;
- `az vm deallocate` as the action that stops compute billing;
- persistence and deletion behavior of the OS disk;
- remaining costs for disks, networking, and Key Vault while deallocated;
- resize guidance through `VM_SIZE` before creation and explicit Azure VM resize afterward.

Acceptance criteria:

- A user can provision, bootstrap, connect to, load secrets on, deallocate, and later restart the Azure host by following the README.
- The documentation distinguishes deallocation from guest shutdown and warns that resource-group deletion removes the retained disk.
- GCP and provider-neutral instructions remain accurate.

## Files expected to change

- Add `infrastructure/azure/provision.sh`
- Add `infrastructure/azure/bootstrap-host.sh`
- Add `infrastructure/azure/put-secret.sh`
- Add `scripts/load-azure-secret.sh`
- Update `scripts/bootstrap.sh`
- Update `.env.example`
- Update `README.md`

The research files and this plan are planning artifacts; no Terraform, Bicep, live Azure deployment, separate data disk, Azure Bastion, VPN, VM scale set, or changes outside `devenv` are included.

## Dependencies and risks

- Local provisioning requires Bash and an authenticated Azure CLI with permission to create resources and role assignments in the selected subscription.
- Secret upload requires the caller to have a Key Vault data-plane writer role; VM secret download relies only on the managed identity.
- Azure role assignments can take several minutes to propagate, so retries must be bounded and failures actionable.
- `Standard_D2s_v5` availability and quota vary by subscription and region; `VM_SIZE` remains configurable.
- A changing client IP requires rerunning provisioning with a new `SSH_CIDR`.
- Deallocated VMs stop compute billing, but their managed disk, public IP, and Key Vault can still incur charges.
- Live end-to-end provisioning is deliberately excluded from automated verification because it mutates the Azure subscription and creates billable resources.

## Implementation sequence

1. Add executable-script test scaffolding and failing behavioral checks after the Test Plan is approved.
2. Implement the Azure provisioner until its validation, command construction, idempotency, and drift checks pass.
3. Implement the bootstrap wrapper and secret upload/download flow.
4. Add the provider-neutral Azure opt-in and provider-conflict behavior.
5. Update examples and README, then run the complete repository verification suite and review the final Git diff.

## Verification commands

The exact test filename may be refined during the red phase without adding dependencies. The intended repository checks are:

```bash
bash tests/azure-scripts-test.sh
bash -n infrastructure/azure/*.sh scripts/*.sh
shellcheck infrastructure/azure/*.sh scripts/*.sh
git diff --check
```

`shellcheck` will be run when already available; installing new tooling is not part of this feature. No verification command will create an Azure resource.

## Test Plan

### Milestone 1: Azure infrastructure provisioning

1. **Valid new environment — integration with stubbed Azure CLI.** Run the provisioner against a deterministic fake `az` executable that reports all resources absent. Verify that the script targets the chosen subscription and emits creation calls for the resource group, network resources, static Standard public IP, NIC, Trusted Launch Ubuntu VM, detached OS-disk policy, RBAC-enabled Key Vault, and vault-scoped VM role assignment. Assert the default VM size is `Standard_D2s_v5`, the disk defaults to 100 GiB `StandardSSD_LRS`, SSH password authentication is unavailable, and the public key—not a private key—is passed.
2. **Configuration overrides — integration with stubbed Azure CLI.** Supply non-default subscription, location, resource names, `VM_SIZE`, disk size/SKU, admin user, key path, and vault. Verify every resulting Azure call uses the overrides consistently and no default subscription leaks into a command.
3. **Unsafe or missing input — unit/command-level.** Independently test a missing `SSH_CIDR`, malformed CIDRs, missing public-key file, invalid or missing Key Vault name, nonnumeric or undersized disk input, unavailable `az`, and unauthenticated Azure CLI. Each must exit nonzero with a useful message before the fake CLI records any mutating call.
4. **Existing compatible environment — integration with stubbed Azure CLI.** Make the fake CLI report compatible resources and identity. Verify the provisioner does not issue duplicate create commands, does update the SSH rule to the requested CIDR, and does not resize, rebuild, or replace the VM.
5. **Incomplete existing environment — integration with stubbed Azure CLI.** Simulate a VM lacking its system identity or vault role. Verify only the missing identity/role is reconciled and the principal ID returned after identity assignment is used for RBAC.
6. **Incompatible drift — integration with stubbed Azure CLI.** Simulate mismatched location, VNet/subnet attachment, NIC association, VM size, security type, disk SKU/size, or vault RBAC mode. Verify each critical incompatibility fails clearly without deleting or replacing resources.
7. **RBAC propagation — integration with stubbed Azure CLI.** Simulate transient principal/role-assignment lookup failures followed by success and verify bounded retries. Simulate permanent failure and verify the script eventually exits with a retryable diagnostic rather than looping forever.
8. **Secret-free summary — regression/security check.** Verify final output contains the intended VM/resource metadata but never contains the SSH key contents, Azure access tokens, or any Key Vault secret value.

### Milestone 2: Host bootstrap and Key Vault secret flow

1. **Azure bootstrap wrapper reuse — integration with stubbed system commands.** Verify the wrapper invokes the provider-neutral bootstrap exactly once, installs Azure CLI only when `az` is absent and installation is enabled, skips installation when already present or disabled, and prints the version when available. Confirm it does not duplicate the neutral workstation package list.
2. **Secret upload validation — unit/command-level.** Exercise valid and invalid secret names, missing env files, empty/readable files, and files above the 25 KB Key Vault limit. Invalid cases must fail before `az keyvault secret set`; a valid file must be passed with UTF-8 encoding and its contents must not appear in output.
3. **Secret rotation — integration with stubbed Azure CLI.** Verify the uploader uses `az keyvault secret set` for both a new and existing secret so Key Vault versioning handles rotation, without granting or changing the human caller's roles.
4. **Managed-identity secret load — integration with stubbed Azure CLI and temporary runtime directory.** Verify the loader calls `az login --identity`, downloads the latest version from `AZURE_KEY_VAULT`, writes outside the Git checkout, produces a mode-600 file inside a mode-700 directory, and prints a safe source command without printing the secret.
5. **Secret load failures — unit/integration.** Cover invalid secret/vault names, absent Azure CLI, managed-identity login failure, Key Vault authorization/propagation failure, download failure, and unavailable runtime directory. Verify partial files are not left readable and errors identify the failing boundary.
6. **Provider selection — integration.** With neither secret variable set, verify bootstrap remains a no-op for secrets. With only the existing GCP variable, verify the GCP loader is still selected. With only the Azure variable, verify the Azure loader is selected. With both, verify bootstrap fails before invoking either loader.
7. **GCP regression — static and integration.** Run the existing GCP scripts through syntax checks and verify Azure additions do not change their flags, environment variables, or secret-file permissions.

### Milestone 3: Documentation and configuration

1. **Example safety — static review.** Verify `.env.example` contains only placeholders, documents both provider variables unambiguously, and contains no token-shaped real value or generated Azure identifier.
2. **Operator journey — manual documentation review.** Follow the README commands conceptually from prerequisites through provisioning, bootstrap, SSH/Zed connection, secret upload/load, deallocation, restart, and resizing. Confirm all referenced scripts and variables exist and names match the implementation.
3. **Lifecycle and cost warnings — static review.** Verify the README distinguishes `az vm deallocate` from guest shutdown, explains OS-disk `Detach`, warns that resource-group deletion removes the disk, and notes continuing disk/IP/Key Vault costs.
4. **Provider-neutral regression — manual review.** Verify generic Ubuntu/Debian and GCP instructions remain complete and do not imply Azure CLI is required on non-Azure hosts.

### Cross-milestone verification and deferred live check

1. **Shell correctness — static.** Run Bash syntax validation over every changed shell script, run ShellCheck if it is already installed, and resolve all errors introduced by this feature.
2. **Repository hygiene — static.** Run the complete local test script, `git diff --check`, inspect executable bits on new scripts, and review the final diff for credentials, private keys, generated files, or unrelated project changes.
3. **Real Azure deployment — deferred end-to-end/manual.** After code review, and only with explicit authorization to create billable resources, run the documented flow in a disposable resource group: provision twice, connect over the restricted SSH route, bootstrap, upload and load a harmless test secret, deallocate/restart, and confirm `/workspace` persists. This live check is not part of the current implementation run.
