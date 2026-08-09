#!/usr/bin/env bash
# GCP wrapper: run the provider-neutral host bootstrap, then add the GCP CLI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

"$REPO_ROOT/scripts/bootstrap-host.sh"

if [[ "${INSTALL_GCLOUD:-1}" == "1" ]] && ! command -v gcloud >/dev/null 2>&1; then
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor --yes -o /usr/share/keyrings/cloud.google.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y google-cloud-cli
fi

if command -v gcloud >/dev/null 2>&1; then
  gcloud --version
fi
