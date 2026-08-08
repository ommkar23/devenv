#!/usr/bin/env bash
# Run on the GCE host as user op. Starts the direct SSH development container.
set -euo pipefail

name=devenv
image=devenv:local

if docker ps --format '{{.Names}}' | grep -Fxq "$name"; then
  echo "$name is already running"
  exit 0
fi

docker rm -f "$name" >/dev/null 2>&1 || true
docker run -d --name "$name" --restart=no --user root \
  --publish 2222:22 \
  --mount type=bind,source=/workspace,target=/workspace \
  --mount type=bind,source=/home/op/.ssh/authorized_keys,target=/home/op/.ssh/authorized_keys,readonly \
  --workdir /workspace/devenv \
  "$image" sh -c 'printf "%s\n" "HERMES_HOME=/workspace/devenv/.hermes" "CODEX_HOME=/workspace/devenv/.codex" > /etc/environment && ln -sf /home/op/.local/bin/hermes /usr/local/bin/hermes && install -d -m 755 -o root -g root /run/sshd && ssh-keygen -A && exec /usr/sbin/sshd -D -e'

echo "devenv started: ssh -p 2222 op@<VM-IP>"
