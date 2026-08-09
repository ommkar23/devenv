#!/usr/bin/env python3
"""Keep every seeded bundled skill disabled in the default Hermes profile."""

from __future__ import annotations

import os
import re
import sys
import tempfile
from pathlib import Path
from typing import NoReturn


SKILL_NAME = re.compile(r"^[A-Za-z0-9._-]+$")


def fail(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def disabled_block(lines: list[str]) -> tuple[int, int]:
    skills_index = next(
        (index for index, line in enumerate(lines) if line.rstrip("\n") == "skills:"),
        None,
    )
    if skills_index is None:
        fail("config.yaml has no top-level skills section")

    disabled_index = None
    for index in range(skills_index + 1, len(lines)):
        line = lines[index]
        stripped = line.strip()
        indent = len(line) - len(line.lstrip())
        if stripped and not stripped.startswith("#") and indent == 0:
            break
        if line.rstrip("\n") == "  disabled:":
            disabled_index = index
            break
    if disabled_index is None:
        fail("config.yaml skills section has no disabled list")

    end = disabled_index + 1
    while end < len(lines):
        line = lines[end]
        stripped = line.strip()
        indent = len(line) - len(line.lstrip())
        if not stripped or indent < 4:
            break
        end += 1
    return disabled_index + 1, end


def main() -> None:
    hermes_home = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes"))
    config_path = hermes_home / "config.yaml"
    manifest_path = hermes_home / "skills" / ".bundled_manifest"

    if not config_path.is_file():
        fail(f"missing Hermes config: {config_path}")
    if not manifest_path.is_file():
        fail(f"missing bundled skill manifest after sync: {manifest_path}")

    bundled = {
        line.partition(":")[0].strip()
        for line in manifest_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }
    invalid = sorted(name for name in bundled if not SKILL_NAME.fullmatch(name))
    if invalid:
        fail(f"invalid skill name(s) in bundled manifest: {', '.join(invalid)}")

    lines = config_path.read_text(encoding="utf-8").splitlines(keepends=True)
    start, end = disabled_block(lines)
    current = {
        match.group(1)
        for line in lines[start:end]
        if (match := re.fullmatch(r"\s{4}-\s+([A-Za-z0-9._-]+)\s*\n?", line))
    }
    desired = sorted(current | bundled)
    added = sorted(bundled - current)

    replacement = [f"    - {name}\n" for name in desired]
    if lines[start:end] == replacement:
        print(f"Bundled skill policy already current ({len(bundled)} disabled).")
        return

    updated = "".join(lines[:start] + replacement + lines[end:])
    fd, temporary_name = tempfile.mkstemp(
        dir=config_path.parent, prefix=".config.yaml.", text=True
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as temporary:
            temporary.write(updated)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.chmod(temporary_name, config_path.stat().st_mode)
        os.replace(temporary_name, config_path)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass

    print(
        f"Disabled {len(added)} newly bundled skill(s); "
        f"{len(bundled)} bundled skill(s) are disabled."
    )


if __name__ == "__main__":
    main()
