#!/usr/bin/env bash
# Idempotently provision the GCP host for the devenv workspace.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-driven-elixir-499108-i5}"
REGION="${REGION:-asia-south1}"
ZONE="${ZONE:-asia-south1-a}"
INSTANCE="${INSTANCE:-devenv-01}"
MACHINE_TYPE="${MACHINE_TYPE:-e2-standard-4}"
BOOT_DISK_GB="${BOOT_DISK_GB:-100}"
SSH_CIDR="${SSH_CIDR:?Set SSH_CIDR, for example 203.0.113.4/32}"
SSH_PUBLIC_KEY_FILE="${SSH_PUBLIC_KEY_FILE:-$HOME/.ssh/id_rsa.pub}"
SERVICE_ACCOUNT_ID="devenv-vm"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
ADDRESS="devenv-ip"
FIREWALL_RULE="devenv-allow-ssh"
NETWORK_TAG="devenv-ssh"

[[ -f "$SSH_PUBLIC_KEY_FILE" ]] || { echo "Missing public key: $SSH_PUBLIC_KEY_FILE" >&2; exit 1; }
[[ "$SSH_CIDR" =~ ^[0-9.]+/[0-9]{1,2}$ ]] || { echo "SSH_CIDR must be a single IPv4 CIDR" >&2; exit 1; }

gcloud config set project "$PROJECT_ID" >/dev/null

if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SERVICE_ACCOUNT_ID" --project="$PROJECT_ID" \
    --display-name="devenv VM service account"
fi

if ! gcloud compute addresses describe "$ADDRESS" --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute addresses create "$ADDRESS" --region="$REGION" --project="$PROJECT_ID"
fi

if ! gcloud compute firewall-rules describe "$FIREWALL_RULE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute firewall-rules create "$FIREWALL_RULE" \
    --project="$PROJECT_ID" --network=default --direction=INGRESS --priority=1000 \
    --action=ALLOW --rules=tcp:22 --source-ranges="$SSH_CIDR" --target-tags="$NETWORK_TAG"
fi

if ! gcloud compute instances describe "$INSTANCE" --zone="$ZONE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  public_key="$(tr -d '\n' < "$SSH_PUBLIC_KEY_FILE")"
  gcloud compute instances create "$INSTANCE" \
    --project="$PROJECT_ID" --zone="$ZONE" --machine-type="$MACHINE_TYPE" \
    --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
    --boot-disk-size="${BOOT_DISK_GB}GB" --boot-disk-type=pd-balanced \
    --address="$ADDRESS" --tags="$NETWORK_TAG" \
    --service-account="$SERVICE_ACCOUNT" --scopes=cloud-platform \
    --metadata="enable-oslogin=FALSE,ssh-keys=op:${public_key}"
fi

gcloud compute instances describe "$INSTANCE" --zone="$ZONE" --project="$PROJECT_ID" \
  --format='yaml(name,status,zone,machineType,networkInterfaces[0].accessConfigs[0].natIP,serviceAccounts.email,disks.initializeParams.diskSizeGb)'
