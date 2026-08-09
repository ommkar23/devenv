#!/usr/bin/env bash
# Upload or rotate one UTF-8 env-file secret in Azure Key Vault.
set -euo pipefail

SECRET_NAME="${1:-}"
ENV_FILE="${2:-}"
KEY_VAULT="${KEY_VAULT:-}"
MAX_SECRET_BYTES=$((25 * 1024))

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

validate_key_vault_name() {
  local name="$1"
  ((${#name} >= 3 && ${#name} <= 24)) || return 1
  [[ "$name" =~ ^[A-Za-z][A-Za-z0-9-]*[A-Za-z0-9]$ ]] || return 1
  [[ "$name" != *--* ]]
}

[[ -n "$SECRET_NAME" && -n "$ENV_FILE" ]] ||
  fail "Usage: put-secret.sh SECRET_NAME ENV_FILE"
[[ "$SECRET_NAME" =~ ^[A-Za-z0-9-]{1,127}$ ]] ||
  fail "Invalid Azure Key Vault secret name"
[[ -n "$KEY_VAULT" ]] || fail "Set KEY_VAULT to the target Azure Key Vault name"
validate_key_vault_name "$KEY_VAULT" || fail "Invalid Azure Key Vault name"
[[ -r "$ENV_FILE" && -f "$ENV_FILE" ]] || fail "Missing or unreadable env file: $ENV_FILE"
[[ -s "$ENV_FILE" ]] || fail "Env file must not be empty"
command -v az >/dev/null 2>&1 || fail "Azure CLI is required"

secret_bytes="$(wc -c <"$ENV_FILE" | tr -d '[:space:]')"
((secret_bytes <= MAX_SECRET_BYTES)) ||
  fail "Env file exceeds the Azure Key Vault 25 KB secret limit"
if command -v iconv >/dev/null 2>&1 && ! iconv -f UTF-8 -t UTF-8 "$ENV_FILE" >/dev/null 2>&1; then
  fail "Env file must contain valid UTF-8"
fi

az_args=(
  keyvault secret set
  --vault-name "$KEY_VAULT"
  --name "$SECRET_NAME"
  --file "$ENV_FILE"
  --encoding utf-8
  --output none
)
if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
  az_args+=(--subscription "$SUBSCRIPTION_ID")
fi
az "${az_args[@]}"

printf 'Secret %s uploaded to Key Vault %s as a new version.\n' "$SECRET_NAME" "$KEY_VAULT"
