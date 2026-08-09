---
name: hermes-installation-troubleshooting
description: "Use when Hermes install, update, profile, or skills drift."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [hermes, installation, update, profiles, skills, troubleshooting]
---

# Hermes Installation and Profile Troubleshooting

Diagnose discrepancies between what Hermes ships and what the active profile exposes. Treat the live Hermes documentation as authoritative, then verify package contents, active home/profile state, and synchronization metadata separately.

## When to use

- A documented or bundled Hermes feature is absent from the current session.
- Skills listed in the Bundled Skills Catalog do not appear in `hermes skills list`.
- An install or update completed but a custom `HERMES_HOME` looks incomplete.
- Different shells, services, ACP sessions, gateways, or profiles expose different configuration.
- Bundled-skill updates appear skipped, deleted, modified, or opted out.

For exact bundled-skill behavior and diagnostic interpretation, read `references/bundled-skill-seeding.md`.

## Core model

Keep these layers distinct:

1. **Installed program/package** — contains the stock `skills/` and `optional-skills/` source trees.
2. **Active Hermes home/profile** — the writable source of truth used by the running session.
3. **Bundled manifest and markers** — record seeding state, local changes, deletions, and opt-out.
4. **Session discovery** — may filter disabled, conditional, unavailable, or externally delegated skills.

A skill existing in the package or online catalog does not prove it has been copied into the active profile.

## Diagnostic workflow

### 1. Establish runtime identity

Check the live installation rather than assuming paths:

```bash
command -v hermes
hermes --version
printf 'HOME=%s\nHERMES_HOME=%s\nHERMES_PROFILE=%s\n' "$HOME" "${HERMES_HOME-}" "${HERMES_PROFILE-}"
hermes config path
hermes skills list
```

If named profiles are involved, repeat checks with the exact profile selector used to launch the affected session.

### 2. Confirm the documented contract

Consult the current Hermes docs, especially:

- Skills System
- Bundled Skills Catalog
- Optional Skills Catalog
- Configuration and profiles documentation

Distinguish **bundled** skills, which are normally seeded, from **official optional** skills, which require explicit installation.

### 3. Compare package source with active profile

Locate the installed package and verify whether its stock `skills/` tree contains the missing skill. Separately inspect the active profile’s `skills/` tree. Do not treat package presence as active installation.

Useful metadata in the active home:

- `skills/.bundled_manifest`
- `.no-bundled-skills`
- `skills/.curator_suppressed`
- skill configuration/disable state

Interpret absence carefully:

- Opt-out marker present: synchronization is intentionally disabled.
- Manifest present, skill absent: deletion may be intentionally respected.
- Manifest entry plus changed local copy: updates may preserve user edits.
- No marker and no manifest: the active home may never have been seeded.

### 4. Audit environment propagation

When a bootstrap script assigns a custom home, ensure it reaches child processes:

```bash
HERMES_HOME=/path/to/home
export HERMES_HOME
```

An unexported shell variable is not inherited by an installer launched through a child shell or pipeline. Also remember that writing `/etc/environment` or a shell profile affects future processes, not the already-running bootstrap shell.

Check every launch surface separately: interactive login shell, service manager, gateway, ACP adapter, scheduled job, and installer/update process.

### 5. Choose the least destructive repair

Do not mutate immediately while diagnosing. First determine whether the profile intentionally opted out and whether its skills are version-controlled or locally customized.

Common official operations include:

```bash
hermes skills opt-in --sync
hermes skills reset <name> --restore
hermes skills list-modified
hermes skills diff <name>
```

Use the narrowest operation that matches the state. A full sync can copy a large catalog and create many repository changes when the profile’s skill directory is tracked.

### 6. Verify after repair

```bash
hermes skills list
```

Also verify the affected session surface, because a long-running process may need a restart or fresh session to rebuild its skill index.

## Bootstrap design rules

- Export `HERMES_HOME` before invoking the installer or updater.
- Prefer explicit environment scoping over relying on future login configuration.
- Run seeding as the intended runtime user when ownership matters.
- Make skill-seeding policy explicit: bundled catalog tracked, ignored, or opt-out.
- Verify the manifest and installed-skill list as part of bootstrap acceptance tests.
- Avoid silently committing generated upstream catalogs into a personal configuration repository.

## Pitfalls

- **Catalog/package/profile conflation** — these are separate layers.
- **Bundled vs optional confusion** — optional repository skills are not active by default.
- **Unexported variables** — shell assignment alone does not configure child processes.
- **Future-only environment files** — profile files do not retroactively alter the current process.
- **Premature sync** — inspect Git policy and local modifications before copying dozens of skills.
- **Wrong profile** — each profile has independent markers and manifests.
- **Assuming every surface auto-syncs** — verify the launch path; do not generalize gateway behavior to all adapters.
- **Overwriting customization** — use manifest-aware commands rather than direct recursive copies.

## Completion criteria

A diagnosis is complete only when it identifies:

1. the active Hermes home/profile,
2. whether the skill exists in package source,
3. whether it exists in the profile,
4. relevant opt-out/manifest/modification state,
5. the environment or lifecycle step that caused divergence,
6. a scoped repair and its repository side effects,
7. post-repair discovery in the affected session surface.
