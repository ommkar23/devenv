#!/usr/bin/env bash
set -euo pipefail

: "${HERMES_HOME:=/workspace/devenv/.hermes}"
export HERMES_HOME

mkdir -p "$HERMES_HOME/skills"

# Opt-in: cloning is runtime work, never part of an image build.
if [[ "${DEVENV_SYNC_PROJECTS:-0}" == "1" ]]; then
  /workspace/devenv/scripts/sync-projects.sh
fi

# Opt-in: secrets are loaded outside the Git checkout.
if [[ -n "${DEVENV_GCP_SECRET:-}" ]]; then
  /workspace/devenv/scripts/load-gcp-secret.sh "$DEVENV_GCP_SECRET"
fi
