# Bundled Skill Seeding: Diagnostic Reference

## Authoritative behavior

Hermes documentation describes two distinct catalogs:

- **Bundled skills** live in the package/repository `skills/` tree and are normally copied into the active profile’s `skills/` directory on install or synchronization.
- **Official optional skills** live under `optional-skills/` and are not active by default; install them explicitly through the official source.

The active profile directory is the runtime source of truth. The package’s stock tree is a source used for seeding and restoration, not necessarily a directory scanned directly by every session.

## Manifest behavior

The active profile’s `skills/.bundled_manifest` records the bundled origin hash for each seeded skill. Synchronization generally follows these cases:

| Profile state | Expected interpretation |
|---|---|
| New upstream skill, no manifest entry | Copy and record it |
| Local copy unchanged | Safe to update from upstream |
| Local copy changed | Preserve user customization |
| Manifest entry exists, local copy deleted | Respect intentional deletion |
| `.no-bundled-skills` exists | Skip bundled seeding |
| No opt-out marker and no manifest | Profile likely never initialized by seeding |

Other mechanisms, such as curator suppression, external skill directories, and per-skill enablement, can also affect discovery.

## Custom-home bootstrap failure pattern

A recurring setup error is:

```bash
HERMES_HOME=/persistent/custom/home
curl ... | bash
```

Because `HERMES_HOME` was assigned but not exported, the child `bash` does not inherit it. The installer may seed its default home while later login sessions use the custom home configured through `/etc/environment` or a profile script.

Correct patterns:

```bash
export HERMES_HOME=/persistent/custom/home
curl ... | bash
```

or:

```bash
curl ... | HERMES_HOME=/persistent/custom/home bash
```

When using a pipeline, verify that the environment assignment applies to the installer process rather than only to the download command.

## Safe investigation sequence

1. Print `HOME`, `HERMES_HOME`, and profile selection in the affected process.
2. Ask Hermes for its config path and installed skill list.
3. Confirm the stock bundled skill exists in the installed package.
4. Inspect the active profile for the skill, manifest, opt-out marker, suppression, and modification state.
5. Inspect bootstrap order and variable export boundaries.
6. Check whether the skills directory is version-controlled before synchronization.
7. Select a manifest-aware restore/sync command.
8. Verify both CLI listing and the originally affected session surface.

## Repair selection

- Re-enable and seed an unintentionally empty profile: `hermes skills opt-in --sync`.
- Restore one missing bundled skill: `hermes skills reset <name> --restore`.
- Before replacing anything locally edited: use `hermes skills list-modified` and `hermes skills diff <name>`.

These commands can modify many files. Explain expected scope first when the skills tree is tracked by Git or shared between profiles.

## Evidence quality

Prefer a layered conclusion such as:

> The stock skill exists in the installed package, but the active profile has neither the skill nor a bundled manifest. The custom home was configured only for future processes, while the installer ran without inheriting it. Therefore the package and active profile diverged before first use.

Avoid claiming that the catalog is stale merely because the active profile is empty, and avoid claiming a feature is unavailable before checking package source and profile state separately.
