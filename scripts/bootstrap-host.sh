#!/usr/bin/env bash
# Provider-neutral host bootstrap for Ubuntu/Debian development VMs.
set -euo pipefail

DEV_USER="${DEV_USER:-op}"
REPO_URL="${REPO_URL:-git@github.com:ommkar23/devenv.git}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace}"
DEVENV_REPO="$WORKSPACE_ROOT/devenv"
HERMES_HOME="$DEVENV_REPO/.hermes"

[[ "${EUID}" -eq 0 ]] || { echo "Run with sudo: sudo $0" >&2; exit 1; }
id "$DEV_USER" >/dev/null

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
  build-essential ca-certificates clang cmake curl direnv fd-find fzf \
  gh git git-lfs gnupg jq less make openssh-client pkg-config procps \
  python3 python3-pip python3-venv ripgrep rsync shellcheck sudo tmux \
  tree unzip vim wget xz-utils yq zip zsh docker.io docker-compose-v2
systemctl enable --now docker
usermod -aG docker "$DEV_USER"
install -d -o "$DEV_USER" -g "$DEV_USER" -m 0755 "$WORKSPACE_ROOT"
install -d -o "$DEV_USER" -g "$DEV_USER" -m 0700 "/home/$DEV_USER/.ssh"
touch "/home/$DEV_USER/.ssh/known_hosts"
chown "$DEV_USER:$DEV_USER" "/home/$DEV_USER/.ssh/known_hosts"
chmod 0644 "/home/$DEV_USER/.ssh/known_hosts"
sudo -u "$DEV_USER" ssh-keyscan -H github.com 2>/dev/null \
  | sort -u - "/home/$DEV_USER/.ssh/known_hosts" > "/tmp/devenv-known-hosts"
install -o "$DEV_USER" -g "$DEV_USER" -m 0644 "/tmp/devenv-known-hosts" \
  "/home/$DEV_USER/.ssh/known_hosts"
rm -f /tmp/devenv-known-hosts

if [[ ! -d "$DEVENV_REPO/.git" ]]; then
  sudo -u "$DEV_USER" git clone "$REPO_URL" "$DEVENV_REPO"
else
  sudo -u "$DEV_USER" git -C "$DEVENV_REPO" pull --ff-only
fi

install -d -o "$DEV_USER" -g "$DEV_USER" -m 0700 "$HERMES_HOME"
install -d -o "$DEV_USER" -g "$DEV_USER" -m 0755 "$HERMES_HOME/skills"

# Make the Hermes configuration home available to interactive shells and ordinary SSH commands.
cat > /etc/profile.d/devenv.sh <<EOF
export HERMES_HOME="$HERMES_HOME"
EOF
chmod 0644 /etc/profile.d/devenv.sh
environment_tmp="$(mktemp)"
grep -v '^\(HERMES_HOME\|CODEX_HOME\)=' /etc/environment > "$environment_tmp" || true
echo "HERMES_HOME=$HERMES_HOME" >> "$environment_tmp"
install -m 0644 "$environment_tmp" /etc/environment
rm -f "$environment_tmp"

# Node.js 22 is required by Codex CLI. Do not reinstall when already present.
if ! command -v node >/dev/null 2>&1 || ! node --version | grep -q '^v22\.'; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi
if ! command -v codex >/dev/null 2>&1; then
  npm install -g @openai/codex
fi

# uv is installed system-wide so it is available to every SSH and Zed shell.
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
fi

# Root-mode is deliberate: the command is in /usr/local/bin while op's runtime
# state remains in the versioned, non-secret config home above.
if ! command -v hermes >/dev/null 2>&1; then
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh \
    | bash -s -- --skip-browser --skip-setup --non-interactive
fi

printf 'Host bootstrap complete. Reconnect as %s, then open /workspace/devenv from Zed over SSH port 22.\n' "$DEV_USER"
