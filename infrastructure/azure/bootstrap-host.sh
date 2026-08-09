#!/usr/bin/env bash
# Azure wrapper: run the provider-neutral host bootstrap, then add Azure CLI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NEUTRAL_BOOTSTRAP="${NEUTRAL_BOOTSTRAP:-$REPO_ROOT/scripts/bootstrap-host.sh}"
AZURE_APT_DISTRIBUTION="${AZURE_APT_DISTRIBUTION:-noble}"
AZURE_APT_ARCHITECTURE="${AZURE_APT_ARCHITECTURE:-amd64}"

"$NEUTRAL_BOOTSTRAP"

if [[ "${INSTALL_AZURE_CLI:-1}" == "1" ]] && ! command -v az >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg

  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor \
    | tee /usr/share/keyrings/microsoft-archive-keyring.gpg >/dev/null
  printf '%s\n' \
    "Types: deb" \
    "URIs: https://packages.microsoft.com/repos/azure-cli/" \
    "Suites: $AZURE_APT_DISTRIBUTION" \
    "Components: main" \
    "Architectures: $AZURE_APT_ARCHITECTURE" \
    "Signed-by: /usr/share/keyrings/microsoft-archive-keyring.gpg" \
    | tee /etc/apt/sources.list.d/azure-cli.sources >/dev/null

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y azure-cli
fi

if command -v az >/dev/null 2>&1; then
  az version
fi
