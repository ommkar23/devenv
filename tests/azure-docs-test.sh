#!/usr/bin/env bash
# Static documentation contract for the Azure VM operator journey.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$ROOT_DIR/README.md"
ENV_EXAMPLE="$ROOT_DIR/.env.example"
FAILURES=0

require_text() {
  local file="$1" description="$2" pattern="$3"
  if ! grep -Eiq -- "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$description" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

reject_text() {
  local file="$1" description="$2" pattern="$3"
  if grep -Eiq -- "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$description" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

require_text "$README" "README documents Azure provisioning" \
  'infrastructure/azure/provision\.sh'
require_text "$README" "README documents the Azure host bootstrap wrapper" \
  'infrastructure/azure/bootstrap-host\.sh'
require_text "$README" "README documents Key Vault upload and managed-identity loading" \
  'infrastructure/azure/put-secret\.sh.*|scripts/load-azure-secret\.sh'
require_text "$README" "README documents compute deallocation" \
  'az vm deallocate'
require_text "$README" "README warns that disk, IP, and Key Vault costs continue while deallocated" \
  '(disk|storage).*(public IP|IP address).*Key Vault.*cost|cost.*(disk|storage).*(public IP|IP address).*Key Vault'
require_text "$README" "README documents OS-disk Detach persistence" \
  '(OS disk|boot disk).*(Detach|persist)|Detach.*(OS disk|boot disk)'
require_text "$README" "README warns resource-group deletion also deletes the retained disk" \
  'resource group.*delet.*disk|delet.*resource group.*disk'

require_text "$ENV_EXAMPLE" ".env.example includes a safe Azure Key Vault placeholder" \
  '^AZURE_KEY_VAULT=(your-|replace-|example-)'
require_text "$ENV_EXAMPLE" ".env.example includes a safe Azure secret-name placeholder" \
  '^DEVENV_AZURE_SECRET=(your-|replace-|example-|devenv-env)'
reject_text "$ENV_EXAMPLE" ".env.example must not contain a real-looking API key or bearer token" \
  '(sk-[A-Za-z0-9_-]{16,}|Bearer[[:space:]]+[A-Za-z0-9._-]{16,})'

if ((FAILURES > 0)); then
  printf '%d Azure documentation assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

printf 'PASS: Azure documentation and example configuration\n'
