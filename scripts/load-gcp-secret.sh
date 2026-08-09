#!/usr/bin/env bash
set -euo pipefail

secret_name="${1:?Usage: load-gcp-secret.sh SECRET_NAME}"
: "${GCP_PROJECT_ID:?Set GCP_PROJECT_ID to the GCP project ID}"

# Avoid path traversal when forming the runtime filename.
[[ "$secret_name" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid secret name" >&2; exit 2; }

# Prefer the user's system runtime directory (normally tmpfs). SSH-only hosts
# may not provide one, so use a per-user private /tmp fallback.
runtime_base="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ ! -d "$runtime_base" || ! -w "$runtime_base" ]]; then
  runtime_base="/tmp/devenv-$(id -u)"
fi
runtime_dir="$runtime_base/devenv/env"
install -d -m 700 "$runtime_dir"
output="$runtime_dir/${secret_name}.env"
umask 077
gcloud secrets versions access latest \
  --project="$GCP_PROJECT_ID" \
  --secret="$secret_name" > "$output"
chmod 600 "$output"
printf 'Loaded %s to %s. Run: source %q\n' "$secret_name" "$output" "$output"
