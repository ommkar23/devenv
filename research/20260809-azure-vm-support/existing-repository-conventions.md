# Existing repository conventions

## Question

How should Azure VM support fit the existing `devenv` architecture without coupling Azure behavior into the provider-neutral bootstrap?

## Summary

The repository already has the right provider boundary:

- `scripts/bootstrap-host.sh` owns the Ubuntu/Debian workstation setup and deliberately installs no cloud CLI.
- `infrastructure/gcp/bootstrap-host.sh` calls the neutral bootstrap, then installs only the GCP CLI.
- `infrastructure/gcp/provision.sh` is an environment-variable-driven, `set -euo pipefail` shell script. It validates inputs, describes before creating, updates mutable firewall state, and prints the resulting VM state.
- `infrastructure/gcp/put-secret.sh` uploads an env file and grants the VM identity access.
- `scripts/load-gcp-secret.sh` validates the secret name and writes plaintext only to a private runtime directory with mode `600`.
- `scripts/bootstrap.sh` makes project sync and secret loading explicit runtime opt-ins.

## Sources

- [`scripts/bootstrap-host.sh`](../../scripts/bootstrap-host.sh)
- [`infrastructure/gcp/provision.sh`](../../infrastructure/gcp/provision.sh)
- [`infrastructure/gcp/bootstrap-host.sh`](../../infrastructure/gcp/bootstrap-host.sh)
- [`infrastructure/gcp/put-secret.sh`](../../infrastructure/gcp/put-secret.sh)
- [`scripts/load-gcp-secret.sh`](../../scripts/load-gcp-secret.sh)
- [`scripts/bootstrap.sh`](../../scripts/bootstrap.sh)
- [`README.md`](../../README.md)

## Implications

Azure support should be self-contained and parallel to GCP:

- `infrastructure/azure/provision.sh`
- `infrastructure/azure/bootstrap-host.sh`
- `infrastructure/azure/put-secret.sh`
- `scripts/load-azure-secret.sh`
- Small provider-neutral integration edits only in `scripts/bootstrap.sh`, `.env.example`, and `README.md`

The Azure wrapper should call the existing neutral bootstrap and then install Azure CLI from Microsoft's apt repository. Microsoft lists Ubuntu 24.04 as supported and recommends package-manager installation. The Azure secret loader should preserve the GCP loader's private runtime-file behavior.

## Risks

- Do not put Azure login state, secret values, SSH private keys, or generated env files in the repository.
- Avoid duplicating workstation packages in the Azure wrapper; the neutral bootstrap remains canonical.
- Existing cloud scripts are shell-only. Adding Bicep or Terraform in this first version would introduce a second provisioning model and unnecessary tooling.
- Provider opt-ins should remain independent. If both GCP and Azure secret variables are set, behavior should be explicit rather than silently choosing one.
