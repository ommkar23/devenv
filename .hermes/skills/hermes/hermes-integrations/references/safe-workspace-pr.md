# Safe PR workflow for portable Hermes workspace changes

Use this when a live Hermes home is inside a Git repository and intentional configuration or reusable skills must be proposed without exposing runtime state.

## Scope and discovery

1. Run `git status --short --ignored` and `git diff` before branching or staging.
2. Classify every changed path. Portable candidates include the repository ignore policy, non-secret `config.yaml`, `SOUL.md`, documentation, and intentionally authored reusable skills. Exclude OAuth/login state, tokens, `.env`, databases and sidecars, locks, caches, logs, memories, downloaded binaries, usage counters, and process metadata.
3. Create a topic branch. Preserve unrelated user changes; do not use destructive cleanup.

## Explicit staging and review

Stage exact safe paths rather than `git add -A` or broad directory globs:

```bash
git add -- .gitignore .hermes/config.yaml <exact-intended-skill-paths>
git diff --cached --name-status
git diff --cached
git diff --cached --check
```

Before committing:

- confirm the staged path list contains only intentional files;
- scan added lines for private-key headers, provider tokens, and credential-like assignments;
- run `hermes config check` when `config.yaml` is included;
- verify representative runtime paths remain ignored and allowlisted configuration paths remain visible with `git check-ignore --no-index`;
- inspect `git status --short --ignored` to ensure credential/runtime files appear only as ignored entries.

A temporary verification script should be created under an OS-safe temporary path, exercise the real repository ignore behavior, and delete itself afterward. Describe it as ad-hoc verification, not as a project test suite.

## Commit, synchronize, and hand off

```bash
git commit -m "chore: sync workspace skills and configuration"
git fetch origin
git rebase origin/main
git diff --check origin/main...HEAD
git diff --name-status origin/main...HEAD
git status --short --branch
git push -u origin <topic-branch>
gh pr create --draft --base main --head <topic-branch> --fill
```

Re-run the focused checks after rebasing because upstream changes can alter ignore behavior or configuration context. Check the working tree again immediately before pushing; if intentional skill files changed during the workflow, inspect, explicitly stage, validate, and amend or commit them rather than silently omitting them.

## GitHub authentication recovery

If fetch works but push reports a read-only SSH key, treat that as an authentication-path problem rather than a repository failure:

1. Preserve the prepared branch and commit; do not restage broadly or recreate the work.
2. Run `gh auth status` without printing credential files or tokens.
3. If unauthenticated and the user is present, run `gh auth login --hostname github.com --git-protocol https --web` and have the user complete the device flow.
4. Run `gh auth setup-git`. If `origin` still uses an SSH URL tied to the read-only key, change only that remote to the repository's HTTPS URL, then retry the push.
5. Verify `HEAD` equals the pushed remote branch before creating the PR.

After `gh pr create`, verify with `gh pr view --json url,title,isDraft,state,baseRefName,headRefName,commits,files`. Require an open draft, the intended base/head, the reviewed file list, matching local/remote commit IDs, and a returned URL before reporting success.

If push or PR creation requires user authentication, preserve the prepared local branch and commit, request only the minimum authentication action, and resume verification afterward. Do not claim that a PR exists until a verifiable URL is returned.