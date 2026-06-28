#!/usr/bin/env bash
#
# prune-all.sh — prune dangling skill symlinks across every registered project.
#
# link-skill.sh records each target project it links into in links.txt (local,
# gitignored, machine-specific absolute paths). This script walks that registry
# and runs prune-skills.sh on each project, so one command cleans up after a
# package update that deleted skills.
#
# Projects whose directory no longer exists are dropped from the registry.
#
# Usage:
#   scripts/prune-all.sh [-n]
#
# Options:
#   -n, --dry-run   Pass through to prune-skills.sh; don't remove links or
#                   rewrite the registry.
#   -h, --help      Show this help.

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

dry_run=0
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) dry_run=1 ;;
    -h|--help)    usage 0 ;;
    *)            echo "error: unknown option: $arg" >&2; usage 1 >&2 ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
registry="$repo_root/links.txt"
prune="$script_dir/prune-skills.sh"

if [ ! -f "$registry" ]; then
  echo "no registry yet ($registry); nothing to prune"
  exit 0
fi

kept=()
gone=()
while IFS= read -r project || [ -n "$project" ]; do
  [ -n "$project" ] || continue
  if [ ! -d "$project" ]; then
    gone+=("$project")
    continue
  fi
  kept+=("$project")
  echo "=== $project ==="
  if [ "$dry_run" -eq 1 ]; then
    "$prune" -n "$project" || echo "warn: prune failed for $project" >&2
  else
    "$prune" "$project" || echo "warn: prune failed for $project" >&2
  fi
done < "$registry"

if [ "${#gone[@]}" -gt 0 ]; then
  echo
  echo "projects no longer on disk (dropped from registry):"
  printf '  - %s\n' "${gone[@]}"
  if [ "$dry_run" -eq 0 ]; then
    printf '%s\n' "${kept[@]:-}" | grep -v '^$' > "$registry" || : > "$registry"
  fi
fi

echo
echo "pruned ${#kept[@]} project(s)"
