#!/usr/bin/env bash
#
# mark-authored.sh — record skill(s) as self-authored in authored.txt.
#
# Skills installed via `npx skills add` are tracked in skills-lock.json, but
# skills you write yourself are not. Without a marker, doctor.sh can't tell a
# self-authored skill apart from a leftover orphan dir. Listing them here lets
# doctor treat them as expected and gen-packages show them separately.
#
# authored.txt is committed (it's part of the repo's own content, unlike the
# machine-specific links.txt). Adding is idempotent and preserves comments.
#
# Usage:
#   scripts/store/mark-authored.sh <skill-name> [<skill-name> ...]
#
# Options:
#   -h, --help    Show this help.

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
src_skills_dir="$repo_root/.agents/skills"
authored="$repo_root/authored.txt"
touch "$authored"

failed=0
for name in "${positional[@]}"; do
  if [ ! -d "$src_skills_dir/$name" ]; then
    echo "error: no such skill in store: $name (looked in $src_skills_dir/$name)" >&2
    failed=1
    continue
  fi
  # Match a bare name line (ignore comments/blanks), exact match.
  if grep -vE '^[[:space:]]*(#|$)' "$authored" 2>/dev/null | grep -qxF "$name"; then
    echo "already marked authored: $name"
    continue
  fi
  echo "$name" >> "$authored"
  echo "marked authored: $name"
done

exit "$failed"
