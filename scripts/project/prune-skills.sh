#!/usr/bin/env bash
#
# prune-skills.sh — remove dangling skill symlinks from a target project.
#
# When a skill is deleted from the central store (e.g. a package update drops
# it), every project that linked it is left with a broken symlink at
# <target>/.agents/skills/<name> pointing at a path that no longer exists.
# This repo doesn't track who linked what, so run this per target project.
#
# It only removes symlinks under <target>/.agents/skills/ that are broken
# (their target no longer resolves). Real files/dirs and still-valid links are
# left untouched. If pruning empties .agents/skills/, the now-useless
# .claude/skills entry link and the empty dir are cleaned up too.
#
# Usage:
#   scripts/project/prune-skills.sh [-n] <target-project-path>
#
# Options:
#   -n, --dry-run   Show what would be removed without removing anything.
#   -h, --help      Show this help.

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

dry_run=0
positional=()
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) dry_run=1 ;;
    -h|--help)    usage 0 ;;
    -*)           echo "error: unknown option: $arg" >&2; usage 1 >&2 ;;
    *)            positional+=("$arg") ;;
  esac
done

if [ "${#positional[@]}" -ne 1 ]; then
  echo "error: need exactly one target project path" >&2
  usage 1 >&2
fi

raw_target="${positional[0]}"
if [ ! -d "$raw_target" ]; then
  echo "error: target project path does not exist: $raw_target" >&2
  exit 1
fi
target="$(cd "$raw_target" && pwd)"
skills_dir="$target/.agents/skills"

if [ ! -d "$skills_dir" ]; then
  echo "nothing to prune: $skills_dir does not exist"
  exit 0
fi

action="removed"
[ "$dry_run" -eq 1 ] && action="would remove"

pruned=0
shopt -s nullglob 2>/dev/null || true

# A broken symlink: -L true, -e false (target doesn't resolve).
for entry in "$skills_dir"/*; do
  if [ -L "$entry" ] && [ ! -e "$entry" ]; then
    dest="$(readlink "$entry")"
    echo "$action broken link: $(basename "$entry") -> $dest"
    [ "$dry_run" -eq 0 ] && rm "$entry"
    pruned=$((pruned + 1))
  fi
done

if [ "$pruned" -eq 0 ]; then
  echo "no broken skill links in $skills_dir"
fi

# If .agents/skills is now empty, clean up the dir and the entry link.
remaining=0
for entry in "$skills_dir"/*; do
  [ -e "$entry" ] || [ -L "$entry" ] && remaining=$((remaining + 1))
done

if [ "$remaining" -eq 0 ]; then
  entry_link="$target/.claude/skills"
  if [ -L "$entry_link" ]; then
    echo "$action empty entry link: .claude/skills -> $(readlink "$entry_link")"
    [ "$dry_run" -eq 0 ] && rm "$entry_link"
  fi
  echo "$action empty dir: .agents/skills"
  [ "$dry_run" -eq 0 ] && rmdir "$skills_dir" 2>/dev/null || true
fi
