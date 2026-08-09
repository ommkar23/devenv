# devenv

Portable, GitHub-backed agentic development environment. The primary workflow is a host-native Linux VM accessed through SSH: this repository is `/workspace/devenv`, and project repositories live at `/workspace/<project-name>`. Docker is available for project services and isolated builds, not as the primary interactive development environment.

## Included

- Hermes CLI with `HERMES_HOME=/workspace/devenv/.hermes`
- Git, Git LFS, GitHub CLI, SSH, Python + uv, Node.js, compilers, CMake, Docker + Compose, tmux, jq/yq, ripgrep, and Google Cloud CLI
- Non-secret Hermes configuration tracked in Git

## Open the environment (primary: host VM)

Provision the VM, clone this repository at `/workspace/devenv`, then run the idempotent host bootstrap as `op`:

```bash
ssh op@<VM-IP> 'cd /workspace/devenv && sudo infrastructure/gcp/bootstrap-host.sh'
```

Reconnect after the script completes (Docker group membership applies on the next login). Zed connects directly to the host SSH service:

```bash
zed ssh://op@<VM-IP>:/workspace/devenv
```

The bootstrap persists:

```bash
HERMES_HOME=/workspace/devenv/.hermes
```

Verify with:

```bash
ssh op@<VM-IP> 'which hermes && hermes --version && printf "%s\n" "$HERMES_HOME"'
```

## Hermes authentication

Hermes credentials—including OpenAI Codex OAuth—are stored in the persistent,
Git-ignored `$HERMES_HOME/auth.json`. They survive normal VM stop/start and
reboots because `/workspace/devenv` is on the VM boot disk.

To authenticate with a ChatGPT/Codex subscription from your Mac, use device
authentication so the VM never tries to open a browser:

```bash
ssh -t op@<VM-IP> 'hermes auth add openai-codex --type oauth --no-browser'
```

Complete the displayed browser flow, then run `hermes model` on the VM to
select OpenAI Codex and the preferred model. Other providers can be added with
`hermes auth add <provider>` or selected through `hermes model`. Do not commit
`auth.json`, API keys, or session data.

## Projects

Add one SSH Git URL per line to `projects.txt`, then run:

```bash
DEVENV_SYNC_PROJECTS=1 /workspace/devenv/scripts/bootstrap.sh
```

Projects are intentionally cloned at runtime—not during host bootstrap—so private Git credentials remain outside setup artifacts and project changes do not require rebuilding the environment.

## GCP Secret Manager

On the GCP VM, attach a service account with `roles/secretmanager.secretAccessor` only for the specific secret(s) needed. Store an env file as a Secret Manager secret, then on the host run:

```bash
export GCP_PROJECT_ID=your-gcp-project
/workspace/devenv/scripts/load-gcp-secret.sh devenv-env
# Source the path printed by the command above.
```

The secret is written with mode `600` under the user's runtime directory (or a private `/tmp` fallback), never to the Git checkout. Do not commit credentials, OAuth tokens, sessions, or `.env` files.

## GCP host

`infrastructure/gcp/provision.sh` creates the GCE VM, a static IP, a firewall limited to one source CIDR on SSH port `22`, and a VM service account. `bootstrap-host.sh` installs the host-native toolchain, Docker, and this repository's runtime configuration. Use a repository deploy key—not a personal SSH key—to clone the private repository.

Stopping the VM when the environment is idle stops compute billing; stopping individual processes does not.
