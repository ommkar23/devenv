#!/usr/bin/env bash
# Run once as root on a fresh Ubuntu 24.04 GCE VM.
set -euo pipefail

DEV_USER="${DEV_USER:-op}"
REPO_URL="${REPO_URL:-git@github.com:ommkar23/devenv.git}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace}"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl docker.io docker-compose-v2 git git-lfs
systemctl enable --now docker
usermod -aG docker "$DEV_USER"
install -d -o "$DEV_USER" -g "$DEV_USER" -m 0755 "$WORKSPACE_ROOT"
sudo -u "$DEV_USER" mkdir -p "/home/$DEV_USER/.ssh"
sudo -u "$DEV_USER" chmod 700 "/home/$DEV_USER/.ssh"
sudo -u "$DEV_USER" ssh-keyscan -H github.com >> "/home/$DEV_USER/.ssh/known_hosts"

if [[ ! -d "$WORKSPACE_ROOT/devenv/.git" ]]; then
  sudo -u "$DEV_USER" git clone "$REPO_URL" "$WORKSPACE_ROOT/devenv"
else
  sudo -u "$DEV_USER" git -C "$WORKSPACE_ROOT/devenv" pull --ff-only
fi

# The user must reconnect after this script so the new docker group applies.
printf 'Host bootstrap complete. Reconnect as %s, then open /workspace/devenv from Zed.\n' "$DEV_USER"
