#!/usr/bin/env bash
set -euo pipefail

: "${HERMES_HOME:=/workspace/devenv/.hermes}"
export HERMES_HOME

DEVENV_ROOT="${DEVENV_ROOT:-/workspace/devenv}"
SYNC_PROJECTS_SCRIPT="${SYNC_PROJECTS_SCRIPT:-$DEVENV_ROOT/scripts/sync-projects.sh}"
GCP_SECRET_LOADER="${GCP_SECRET_LOADER:-$DEVENV_ROOT/scripts/load-gcp-secret.sh}"
AZURE_SECRET_LOADER="${AZURE_SECRET_LOADER:-$DEVENV_ROOT/scripts/load-azure-secret.sh}"

if [[ -n "${DEVENV_GCP_SECRET:-}" && -n "${DEVENV_AZURE_SECRET:-}" ]]; then
  printf 'Set only one of DEVENV_GCP_SECRET or DEVENV_AZURE_SECRET.\n' >&2
  exit 2
fi

mkdir -p "$HERMES_HOME/skills"

# Opt-in: cloning is runtime work, never part of an image build.
if [[ "${DEVENV_SYNC_PROJECTS:-0}" == "1" ]]; then
  "$SYNC_PROJECTS_SCRIPT"
fi

# Opt-in: secrets are loaded outside the Git checkout.
if [[ -n "${DEVENV_GCP_SECRET:-}" ]]; then
  "$GCP_SECRET_LOADER" "$DEVENV_GCP_SECRET"
elif [[ -n "${DEVENV_AZURE_SECRET:-}" ]]; then
  "$AZURE_SECRET_LOADER" "$DEVENV_AZURE_SECRET"
fi
