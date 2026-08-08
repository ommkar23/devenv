#!/usr/bin/env bash
set -euo pipefail

workspace=/workspace
list=/workspace/devenv/projects.txt

[[ -f "$list" ]] || { echo "Missing $list" >&2; exit 1; }

while IFS= read -r url || [[ -n "$url" ]]; do
  [[ -z "$url" || "$url" == \#* ]] && continue
  name="$(basename "${url%/}" .git)"
  target="$workspace/$name"

  if [[ -d "$target/.git" ]]; then
    echo "Updating $name"
    git -C "$target" fetch --prune
    git -C "$target" pull --ff-only
  elif [[ -e "$target" ]]; then
    echo "Refusing to replace non-Git path: $target" >&2
  else
    echo "Cloning $name"
    git clone "$url" "$target"
  fi
done < "$list"
