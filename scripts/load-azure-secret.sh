#!/usr/bin/env bash
# Load the latest Azure Key Vault secret with the VM's managed identity.
set -euo pipefail

secret_name="${1:-}"
AZURE_KEY_VAULT="${AZURE_KEY_VAULT:-}"
temporary_output=""

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$temporary_output" && -f "$temporary_output" ]]; then
    rm -f -- "$temporary_output"
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

[[ -n "$secret_name" ]] || fail "Usage: load-azure-secret.sh SECRET_NAME"
[[ "$secret_name" =~ ^[A-Za-z0-9-]{1,127}$ ]] || fail "Invalid Azure Key Vault secret name"
[[ -n "$AZURE_KEY_VAULT" ]] || fail "Set AZURE_KEY_VAULT to the Azure Key Vault name"
[[ "$AZURE_KEY_VAULT" =~ ^[A-Za-z][A-Za-z0-9-]{1,22}[A-Za-z0-9]$ ]] ||
  fail "Invalid Azure Key Vault name"
[[ "$AZURE_KEY_VAULT" != *--* ]] || fail "Invalid Azure Key Vault name"
command -v az >/dev/null 2>&1 || fail "Azure CLI is required"

az login --identity --allow-no-subscriptions --output none || fail "Managed-identity login failed"

runtime_base="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ ! -d "$runtime_base" || ! -w "$runtime_base" ]]; then
  runtime_base="/tmp/devenv-$(id -u)"
fi
runtime_dir="$runtime_base/devenv/env"
install -d -m 700 "$runtime_dir"
output="$runtime_dir/${secret_name}.env"
umask 077
temporary_output="$(mktemp "$runtime_dir/.${secret_name}.XXXXXX")"

secret_args=(
  keyvault secret download
  --vault-name "$AZURE_KEY_VAULT"
  --name "$secret_name"
  --file "$temporary_output"
  --encoding utf-8
  --overwrite
  --output none
)
if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
  secret_args+=(--subscription "$SUBSCRIPTION_ID")
fi
if ! az "${secret_args[@]}"; then
  fail "Could not load secret $secret_name from Key Vault $AZURE_KEY_VAULT"
fi

chmod 600 "$temporary_output"
mv -f -- "$temporary_output" "$output"
temporary_output=""
printf 'Loaded %s from Azure Key Vault to %s. Run: source %q\n' "$secret_name" "$output" "$output"
