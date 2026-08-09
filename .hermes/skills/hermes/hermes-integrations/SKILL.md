---
name: hermes-integrations
description: Use when configuring Hermes MCP servers and integrations.
version: 1.0.0
author: Hermes Curator
license: MIT
metadata:
  hermes:
    tags:
      - hermes
      - mcp
      - integrations
      - configuration
    related_skills: []
---

# Hermes Integrations

Configure and validate external Hermes integrations, especially Model Context Protocol (MCP) servers. Prefer Hermes' management commands over editing security-sensitive configuration files directly.

## When to Use

Use this skill when adding, removing, testing, or troubleshooting an MCP server; translating a supplied MCP YAML snippet into live Hermes configuration; or determining whether newly installed integration tools are available to the current session.

## MCP server workflow

1. **Inspect before changing anything.**
   - Check `hermes mcp --help` and the relevant subcommand help when syntax may vary by Hermes version.
   - Check `hermes mcp list` to avoid duplicating an existing server name.
   - If reviewing config, preserve unrelated user changes.

2. **Add through the Hermes CLI.**
   - For an HTTP MCP endpoint, use:
     `hermes mcp add <name> --url <https-url>`
   - Run interactive setup in a PTY because Hermes may ask about authentication and which discovered tools to enable.
   - Answer the authentication prompt from known endpoint requirements; do not invent credentials or request a token when the server works anonymously.
   - Review discovered tools, then enable the requested set.

3. **Verify the saved integration.**
   - Run `hermes mcp list` and confirm the server is enabled.
   - Run `hermes mcp test <name>` and require a successful connection plus tool discovery before reporting completion.
   - Confirm the saved config contains the expected `mcp_servers` entry without exposing secrets.

4. **Set restart expectations.**
   - MCP tools are loaded when a Hermes session starts. Tell the user to begin a new session when the installer reports that one is required.
   - Do not imply the newly added tools are available in the current session unless they actually appear in the active tool schema.

## Direct configuration snippets

A user may provide YAML such as:

```yaml
mcp_servers:
  example:
    url: https://example.com/mcp
```

Treat this as the desired end state, but prefer `hermes mcp add` because it performs discovery, records enablement, and respects Hermes' config protections. If the CLI normalizes or augments the YAML, verify semantic equivalence rather than insisting on byte-for-byte formatting.

## Version-controlling personal Hermes configuration

When a repository versions a Hermes home, distinguish durable personal configuration from machine-generated state.

1. Inspect the existing tracked set with Git before changing ignore rules; preserve intentional tracked files and unrelated user edits.
2. Prefer an allowlist for `.hermes/` when the user's intent is “personal configuration only.” Typical candidates are `config.yaml`, `SOUL.md`, and a repository README. Do not automatically include credentials, databases, sessions, caches, downloaded binaries or skills, usage metadata, process files, or learned memories.
3. Remember that ignore rules do not untrack files already in Git. Review the tracked set separately and obtain consent before removing anything from the index.
4. Verify both sides of the contract: intended configuration remains versionable, representative runtime artifacts are ignored, and no unexpected `.hermes` files appear in `git status`.
5. After changing ignore behavior, run a focused temporary verification script from an OS-safe temp path, execute it against the real repository behavior, report that it is ad-hoc verification rather than a project test-suite result, and remove it afterward.

See `references/version-controlled-hermes-home.md` for a reusable allowlist pattern and verification checklist.

## Proposing portable workspace changes

When moving intentional Hermes configuration or skills through Git, use a review-first topic-branch and draft-PR workflow:

1. Classify all changed and ignored paths before staging; login state, tokens, `.env`, credentials, databases, caches, locks, logs, memories, binaries, and runtime metadata must remain excluded.
2. Stage exact safe paths rather than `git add -A` or broad globs, then review both `git diff --cached --name-status` and the full staged diff.
3. Validate the staged state with `git diff --cached --check`, a focused secret-pattern scan, `hermes config check` when applicable, and allowlist/runtime-ignore probes.
4. Commit, fetch, and rebase onto the current base branch; repeat the focused path and diff checks after rebasing before pushing.
5. Create a draft PR and verify its base, head, file list, draft state, and URL. If authentication requires user action, preserve the prepared branch and commit and report the narrow blocker rather than claiming completion.

See `references/safe-workspace-pr.md` for the complete staging, verification, synchronization, and handoff sequence.

## Toolset status and runtime availability

When explaining `hermes tools list`, distinguish three layers: platform configuration, the active session's injected tool schema, and operational readiness (dependencies, credentials, connectivity, and environment support). The command defaults to the `cli` platform, so its output must not be assumed to describe ACP or every gateway surface. Treat rows as toolsets rather than individual callable tools, and treat an MCP server's `all tools enabled` status as a filtering decision rather than a connectivity test. See `references/toolset-runtime-availability.md` for the diagnostic sequence and wording guidance.

## Pitfalls

- A non-PTY invocation can block or cancel at authentication/tool-selection prompts. Relaunch interactively rather than treating that cancellation as a server failure.
- A successful initial connection is not enough; verify with `hermes mcp test` after saving.
- Do not overwrite the full config merely to add one integration.
- Do not report web-search capability until the MCP tools are loaded into the active session.
- Do not equate `✓ enabled` in `hermes tools list` with a callable tool in an already-running session; report the named platform and inspect the active schema.
- Avoid broad negative claims when platform configuration and active-session exposure differ. State the scoped discrepancy instead.
- A long denylist for Hermes runtime files is fragile because new cache and state files appear over time; use a narrow allowlist when only personal configuration belongs in version control.
- Do not treat memory files as ordinary preferences by default: they may contain learned personal facts or sensitive context. Version them only when the user explicitly requests that scope.

## References

- `references/parallel-search.md` — validated anonymous HTTP MCP example for Parallel Search.
- `references/safe-workspace-pr.md` — explicit staging, secret-safe verification, rebase, and draft-PR handoff for portable Hermes workspace changes.
- `references/toolset-runtime-availability.md` — interpreting `hermes tools list` versus active-session tool exposure.
- `references/version-controlled-hermes-home.md` — allowlisting personal Hermes configuration and verifying ignore behavior.
