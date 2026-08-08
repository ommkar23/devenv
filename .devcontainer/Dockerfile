FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates clang cmake curl direnv fd-find fzf \
    git git-lfs gnupg2 jq less make openssh-client openssh-server pkg-config procps \
    python3 python3-pip python3-venv ripgrep rsync shellcheck sudo tmux \
    tree unzip vim wget yq zip zsh \
    && rm -rf /var/lib/apt/lists/*

# Match the GCE host's `op` UID (1001), so /workspace bind mounts stay writable.
RUN groupadd --gid 1001 op \
    && useradd --uid 1001 --gid 1001 --create-home --shell /bin/bash op \
    && usermod -aG sudo op \
    && printf 'op ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/op \
    && chmod 440 /etc/sudoers.d/op \
    && install -d -o op -g op -m 700 /home/op/.ssh \
    && install -d -m 755 /run/sshd \
    && printf '%s\n' 'PasswordAuthentication no' 'PermitRootLogin no' 'PubkeyAuthentication yes' 'AllowUsers op' > /etc/ssh/sshd_config.d/devenv.conf

# Node.js is required for Codex CLI.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @openai/codex \
    && rm -rf /var/lib/apt/lists/*

# uv provides fast, isolated Python tooling.
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Used at runtime to fetch Secret Manager values via a GCP VM service account.
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
      > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

USER op

# Skip Playwright/Chromium: Zed handles editor browsing, and this prevents a huge image build.
RUN env -u HERMES_HOME bash -c 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser --skip-setup --non-interactive'

ENV PATH="/home/op/.local/bin:${PATH}"
ENV HERMES_HOME="/workspace/devenv/.hermes"
ENV CODEX_HOME="/workspace/devenv/.codex"
WORKDIR /workspace/devenv
