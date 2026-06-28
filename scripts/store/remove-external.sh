#!/usr/bin/env bash
#
# remove-external.sh — remove a GitHub-hosted skill added with add-external.sh.
#
# Undoes add-external for one or more skills: deletes the store symlink, drops
# the entry from external.json, and removes the .gitignore line. The cloned
# repo under $SKILLS_CODE_ROOT is left in place (it may hold other skills, and
# it's part of your code tree) — its path is printed so you can delete it if you
# want.
#
# Usage:
#   scripts/store/remove-external.sh <name> [<name> ...]
#
# Options:
#   -h, --help    Show this help.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
# shellcheck source=../lib/external.sh
. "$script_dir/../lib/external.sh"
manifest="$repo_root/external.json"

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

positional=()
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage 0 ;;
    -*)        echo "error: unknown option: $arg" >&2; usage 1 >&2 ;;
    *)         positional+=("$arg") ;;
  esac
done

if [ "${#positional[@]}" -lt 1 ]; then
  echo "error: need at least one skill name" >&2
  usage 1 >&2
fi

# Names currently recorded as external.
known="$(external_names "$manifest" 2>/dev/null || true)"

failed=0
for name in "${positional[@]}"; do
  if ! printf '%s\n' "$known" | grep -qxF "$name"; then
    echo "error: not an external skill in external.json: $name" >&2
    failed=1
    continue
  fi

  # Resolve the repo's clone dir from the manifest before we drop the entry.
  repo="$(external_rows "$manifest" | awk -F'\t' -v n="$name" '$1==n {print $2}')"
  clonedir=""
  [ -n "$repo" ] && clonedir="$(clone_dir_for "$repo")"

  dest="$repo_root/.agents/skills/$name"
  if [ -L "$dest" ]; then
    rm "$dest"
    echo "removed symlink: .agents/skills/$name"
  elif [ -e "$dest" ]; then
    echo "warn: $dest exists and is not a symlink; leaving it" >&2
  fi

  manifest_remove "$manifest" "$name"
  echo "dropped from external.json: $name"

  gitignore_remove "$repo_root" "/.agents/skills/$name"
  echo "removed gitignore line: /.agents/skills/$name"

  if [ -n "$clonedir" ] && [ -d "$clonedir" ]; then
    echo "note: clone left in place (delete manually if unused): $clonedir"
  fi
done

exit "$failed"
