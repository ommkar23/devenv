#!/usr/bin/env bash
# Upload or rotate one env-file secret and grant only devenv VM access to it.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-driven-elixir-499108-i5}"
SECRET_NAME="${1:?Usage: put-secret.sh SECRET_NAME ENV_FILE}"
ENV_FILE="${2:?Usage: put-secret.sh SECRET_NAME ENV_FILE}"
SERVICE_ACCOUNT="devenv-vm@${PROJECT_ID}.iam.gserviceaccount.com"

[[ "$SECRET_NAME" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid secret name" >&2; exit 2; }
[[ -f "$ENV_FILE" ]] || { echo "Missing env file: $ENV_FILE" >&2; exit 1; }

gcloud config set project "$PROJECT_ID" >/dev/null
if ! gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud secrets create "$SECRET_NAME" --project="$PROJECT_ID" --replication-policy=automatic
fi

gcloud secrets versions add "$SECRET_NAME" --project="$PROJECT_ID" --data-file="$ENV_FILE"
gcloud secrets add-iam-policy-binding "$SECRET_NAME" --project="$PROJECT_ID" \
  --member="serviceAccount:$SERVICE_ACCOUNT" --role="roles/secretmanager.secretAccessor" --quiet >/dev/null
printf 'Secret %s uploaded; access granted only to %s\n' "$SECRET_NAME" "$SERVICE_ACCOUNT"
