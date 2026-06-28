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
external_file="$repo_root/external.json"
# shellcheck source=lib-external.sh
. "$script_dir/lib-external.sh"

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

authored_file="$repo_root/authored.txt"
read_authored() {
  [ -f "$authored_file" ] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$authored_file" 2>/dev/null || true
}

# Sorted name sets. A dir is a skill only if it contains SKILL.md; other dirs
# (dev workspaces, scratch) are ignored.
locked="$(lock_skills | sort)"
present="$(cd "$skills_dir" && for d in */; do [ -f "$d/SKILL.md" ] && echo "${d%/}" || :; done | sort)"
non_skill="$(cd "$skills_dir" && for d in */; do { [ -d "$d" ] && [ ! -f "$d/SKILL.md" ] && echo "${d%/}"; } || :; done | sort)"
authored="$(read_authored | sort -u)"
external="$(external_names "$external_file" | sort -u)"

# A store dir is fine if it's in the lockfile, marked self-authored, or external.
managed="$(printf '%s\n%s\n%s\n' "$locked" "$authored" "$external" | grep -v '^$' | sort -u)"
orphans="$(comm -13 <(printf '%s\n' "$managed") <(printf '%s\n' "$present"))"
missing="$(comm -23 <(printf '%s\n' "$locked") <(printf '%s\n' "$present"))"
# external skills with no resolvable dir (clone missing / link broken).
missing_external="$(comm -23 <(printf '%s\n' "$external") <(printf '%s\n' "$present"))"
# authored.txt names that have no dir (stale entries).
authored_stale="$(comm -23 <(printf '%s\n' "$authored") <(printf '%s\n' "$present"))"
# present skills per category (for the ok summary).
authored_present="$(comm -12 <(printf '%s\n' "$authored") <(printf '%s\n' "$present"))"
external_present="$(comm -12 <(printf '%s\n' "$external") <(printf '%s\n' "$present"))"

problems=0

if [ -n "$orphans" ]; then
  problems=1
  echo "orphan dirs (not in lockfile, authored.txt, or external.json):"
  printf '%s\n' "$orphans" | sed 's/^/  - /'
  echo "  fix: package leftover -> npx skills remove <name> (or delete the dir)"
  echo "       wrote it yourself -> scripts/mark-authored.sh <name>"
  echo "       from a GitHub repo -> scripts/add-external.sh <repo> <path> <name>"
fi

if [ -n "$missing" ]; then
  problems=1
  echo "missing dirs (in lockfile but not in .agents/skills/):"
  printf '%s\n' "$missing" | sed 's/^/  - /'
  echo "  fix: npx skills experimental_install"
fi

if [ -n "$missing_external" ]; then
  problems=1
  echo "missing external skills (in external.json but no resolvable dir):"
  printf '%s\n' "$missing_external" | sed 's/^/  - /'
  echo "  fix: scripts/sync-external.sh"
fi

if [ -n "$authored_stale" ]; then
  echo "warn: authored.txt lists skills with no dir (stale entries):"
  printf '%s\n' "$authored_stale" | sed 's/^/  - /'
  echo "      remove them from authored.txt"
fi

if [ -n "$non_skill" ]; then
  echo "info: ignored non-skill dirs (no SKILL.md):"
  printf '%s\n' "$non_skill" | sed 's/^/  - /'
fi

if [ "$problems" -eq 0 ]; then
  lcount="$(printf '%s\n' "$locked" | grep -c . || true)"
  acount="$(printf '%s\n' "$authored_present" | grep -c . || true)"
  ecount="$(printf '%s\n' "$external_present" | grep -c . || true)"
  echo "ok: store agrees with manifests ($lcount installed, $acount self-authored, $ecount external)"
  exit 0
fi

echo
echo "after fixing, run scripts/gen-packages.sh to refresh PACKAGES.md"
exit 1
