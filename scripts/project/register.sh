#!/usr/bin/env bash
#
# register.sh — record project(s) in the links.txt registry.
#
# link-skill.sh registers targets automatically, but projects you linked by
# hand (before using these scripts, or with a manual `ln -s`) won't be in the
# registry and so prune-all.sh can't find them. Use this to add them.
#
# The registry holds machine-specific absolute paths and stays local
# (gitignored). Adding is idempotent and the file is kept sorted & unique.
#
# Usage:
#   scripts/project/register.sh <project-path> [<project-path> ...]
#   scripts/project/register.sh -r <project-path> [<project-path> ...]
#
# Options:
#   -r, --remove  De-register the project(s) instead of adding them.
#   -h, --help    Show this help.

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

remove=0
positional=()
for arg in "$@"; do
  case "$arg" in
    -r|--remove) remove=1 ;;
    -h|--help)   usage 0 ;;
    -*)          echo "error: unknown option: $arg" >&2; usage 1 >&2 ;;
    *)           positional+=("$arg") ;;
  esac
done

if [ "${#positional[@]}" -lt 1 ]; then
  echo "error: need at least one project path" >&2
  usage 1 >&2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
registry="$repo_root/links.txt"
touch "$registry"

# Resolve to an absolute path; fall back to the literal arg if the dir is gone.
abspath() { if [ -d "$1" ]; then (cd "$1" && pwd); else printf '%s\n' "$1"; fi; }

failed=0
for raw in "${positional[@]}"; do
  project="$(abspath "$raw")"

  if [ "$remove" -eq 1 ]; then
    if grep -qxF "$project" "$registry"; then
      grep -vxF "$project" "$registry" > "$registry.tmp" && mv "$registry.tmp" "$registry"
      echo "deregistered: $project"
    else
      echo "not registered: $project"
    fi
    continue
  fi

  if [ ! -d "$raw" ]; then
    echo "error: project path does not exist: $raw" >&2
    failed=1
    continue
  fi
  if [ "$project" = "$repo_root" ]; then
    echo "error: refusing to register the skills repo itself" >&2
    failed=1
    continue
  fi
  if grep -qxF "$project" "$registry"; then
    echo "already registered: $project"
    continue
  fi

  echo "$project" >> "$registry"
  sort -u "$registry" -o "$registry"
  echo "registered project in links.txt: $project"

  if [ ! -d "$project/.agents/skills" ]; then
    echo "  note: $project/.agents/skills not found — no skills linked there yet?" >&2
  fi
done

exit "$failed"
