# Version-controlled Hermes home

Use this pattern when a repository should contain only durable personal Hermes configuration, not the entire live Hermes home.

## Narrow allowlist

```gitignore
# Keep only intentional personal configuration from the Hermes home.
.hermes/*
!.hermes/README.md
!.hermes/SOUL.md
!.hermes/config.yaml
```

Adapt the exceptions to the repository's explicit policy. A tracked README can document the boundary; `SOUL.md` captures intentional behavior preferences; `config.yaml` captures non-secret model, tool, and integration choices.

Do not add exceptions by default for:

- credentials, OAuth material, or lock files;
- databases, WAL/SHM sidecars, sessions, logs, or process state;
- caches, generated notices, downloaded binaries, or verification evidence;
- Skill Hub downloads and usage metadata;
- memory files, which may contain learned personal facts or sensitive context.

## Discovery before editing

1. Read the current `.gitignore` and repository policy files.
2. Run `git status --short --untracked-files=all`.
3. Run `git ls-files .hermes` to identify files already tracked; `.gitignore` cannot untrack them.
4. Inspect only enough of the Hermes home to classify files. Never print credential contents.
5. Preserve existing user modifications to tracked configuration.

## Verification contract

Verify all of the following after editing:

- `git diff --check` succeeds.
- `git status --short --untracked-files=all` shows only intended tracked configuration changes.
- `git check-ignore -v --no-index <runtime-path>` confirms representative runtime artifacts are ignored.
- `git check-ignore --quiet --no-index <allowed-path>` returns nonzero for each allowlisted configuration file.
- `hermes config check` validates the tracked configuration without exposing secrets.

Create a focused temporary script with an OS-safe path such as Python's `tempfile.mkstemp(prefix="hermes-verify-", suffix=".py")`. Have it assert both the allowed and ignored sets against the actual repository, run it, report it explicitly as ad-hoc verification rather than the project test suite, and delete it in a `finally` block.

## Important Git behavior

Ignore rules affect only untracked files. If generated state is already tracked, do not silently run `git rm --cached`; show the tracked set and obtain user consent before changing the index.
