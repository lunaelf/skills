#!/usr/bin/env bash
#
# doctor.sh — check that the central store and skills-lock.json agree.
#
# skills-lock.json lists every installed skill (and its source package); the
# skills themselves live in .agents/skills/<name>/. After a package update,
# remove, or a half-finished sync these can drift apart:
#
#   - orphan dir : .agents/skills/<name> exists but no lock entry  -> leftover;
#                  `npx skills remove <name>` or delete the dir.
#   - missing dir: lock entry exists but .agents/skills/<name> is gone -> run
#                  `npx skills experimental_install` to restore it.
#
# Exits non-zero if any mismatch is found, so it can gate commits / CI.
#
# Usage:
#   scripts/doctor.sh
#
# Options:
#   -h, --help    Show this help.

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage 0 ;;
    *)         echo "error: unknown option: $arg" >&2; usage 1 >&2 ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
skills_dir="$repo_root/.agents/skills"
lock_file="$repo_root/skills-lock.json"

[ -f "$lock_file" ] || { echo "error: lockfile not found: $lock_file" >&2; exit 1; }
[ -d "$skills_dir" ] || { echo "error: store not found: $skills_dir" >&2; exit 1; }

lock_skills() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.skills | keys[]' "$lock_file"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; [print(k) for k in json.load(open(sys.argv[1])).get("skills",{})]' "$lock_file"
  else
    echo "error: need jq or python3 to read $lock_file" >&2
    return 2
  fi
}

# Sorted name sets.
locked="$(lock_skills | sort)"
present="$(cd "$skills_dir" && for d in */; do [ -d "$d" ] && echo "${d%/}"; done | sort)"

orphans="$(comm -13 <(printf '%s\n' "$locked") <(printf '%s\n' "$present"))"
missing="$(comm -23 <(printf '%s\n' "$locked") <(printf '%s\n' "$present"))"

problems=0

if [ -n "$orphans" ]; then
  problems=1
  echo "orphan dirs (in .agents/skills/ but not in lockfile):"
  printf '%s\n' "$orphans" | sed 's/^/  - /'
  echo "  fix: npx skills remove <name>  (or delete the dir)"
fi

if [ -n "$missing" ]; then
  problems=1
  echo "missing dirs (in lockfile but not in .agents/skills/):"
  printf '%s\n' "$missing" | sed 's/^/  - /'
  echo "  fix: npx skills experimental_install"
fi

if [ "$problems" -eq 0 ]; then
  count="$(printf '%s\n' "$locked" | grep -c . || true)"
  echo "ok: store and lockfile agree ($count skills)"
  exit 0
fi

echo
echo "after fixing, run scripts/gen-packages.sh to refresh PACKAGES.md"
exit 1
