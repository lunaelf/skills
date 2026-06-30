#!/usr/bin/env bash
#
# unlink-skill.sh — remove skill symlinks from a project (the inverse of
# link-skill.sh). Unlike prune-skills.sh (which only removes *broken* links),
# this removes the named links whether or not they still resolve.
#
# Each argument is a skill name or a package (expanded to its members), matching
# link-skill.sh. Only symlinks are removed; real files/dirs are refused. In
# global mode (-g) only links into THIS repo's store are touched.
#
# Project mode removes <target>/.agents/skills/<name>; if that empties the dir,
# the .claude/skills entry link and the empty dir are cleaned up too.
# Global mode removes ~/.agents/skills/<name> and ~/.claude/skills/<name>.
#
# Usage:
#   scripts/project/unlink-skill.sh [-n] <target-project-path> <skill-or-package> ...
#   scripts/project/unlink-skill.sh [-n] -g <skill-or-package> ...
#
# Options:
#   -g, --global    Unlink from ~/.agents/skills + ~/.claude/skills (no target).
#   -n, --dry-run   Show what would be removed without removing anything.
#   -h, --help      Show this help.

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

dry_run=0
global=0
positional=()
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) dry_run=1 ;;
    -g|--global)  global=1 ;;
    -h|--help)    usage 0 ;;
    -*)           echo "error: unknown option: $arg" >&2; usage 1 >&2 ;;
    *)            positional+=("$arg") ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
src_skills_dir="$repo_root/.agents/skills"
lock_file="$repo_root/skills-lock.json"
# shellcheck source=../lib/lock.sh
. "$script_dir/../lib/lock.sh"

if [ "$global" -eq 1 ]; then
  if [ "${#positional[@]}" -lt 1 ]; then
    echo "error: -g needs at least one skill or package name" >&2
    usage 1 >&2
  fi
  inputs=("${positional[@]}")
else
  if [ "${#positional[@]}" -lt 2 ]; then
    echo "error: need a target path and at least one skill or package name" >&2
    usage 1 >&2
  fi
  raw_target="${positional[0]}"
  inputs=("${positional[@]:1}")
  if [ ! -d "$raw_target" ]; then
    echo "error: target project path does not exist: $raw_target" >&2
    exit 1
  fi
  target="$(cd "$raw_target" && pwd)"
fi

action="removed"
[ "$dry_run" -eq 1 ] && action="would remove"

unlink_one() {
  local name="$1" dest="$target/.agents/skills/$name"
  if [ -L "$dest" ]; then
    echo "$action link: $name -> $(readlink "$dest")"
    [ "$dry_run" -eq 0 ] && rm "$dest"
  elif [ -e "$dest" ]; then
    echo "skip (not a symlink): $name" >&2
  else
    echo "not linked: $name"
  fi
}

unlink_global_one() {
  local name="$1" agents="$HOME/.agents/skills/$name" claude="$HOME/.claude/skills/$name"
  if [ -L "$agents" ]; then
    case "$(readlink "$agents")" in
      "$src_skills_dir"/*) ;;
      *) echo "skip (not linked from this repo): $name" >&2; return 0 ;;
    esac
    echo "$action global link: $name"
    [ "$dry_run" -eq 0 ] && rm "$agents"
    if [ -L "$claude" ] && [ "$(readlink "$claude")" = "../../.agents/skills/$name" ]; then
      [ "$dry_run" -eq 0 ] && rm "$claude"
    fi
  elif [ -e "$agents" ]; then
    echo "skip (not a symlink): $name" >&2
  else
    echo "not linked globally: $name"
  fi
}

# --- resolve inputs (shared with link-skill) --------------------------------

failed=0
resolved=()
resolved_out="$(resolve_skill_inputs "$lock_file" "$src_skills_dir" "${inputs[@]}")" || failed=1
while IFS= read -r name; do
  [ -n "$name" ] && resolved+=("$name")
done <<EOF
$resolved_out
EOF

for name in "${resolved[@]:-}"; do
  [ -n "$name" ] || continue
  if [ "$global" -eq 1 ]; then
    unlink_global_one "$name" || failed=1
  else
    unlink_one "$name" || failed=1
  fi
done

# Project mode: if .agents/skills is now empty, clean up dir + entry link.
if [ "$global" -eq 0 ] && [ "$dry_run" -eq 0 ] && [ -d "$target/.agents/skills" ]; then
  remaining=0
  shopt -s nullglob 2>/dev/null || true
  for entry in "$target/.agents/skills"/*; do
    if [ -e "$entry" ] || [ -L "$entry" ]; then remaining=$((remaining + 1)); fi
  done
  if [ "$remaining" -eq 0 ]; then
    entry_link="$target/.claude/skills"
    if [ -L "$entry_link" ]; then
      echo "removed empty entry link: .claude/skills -> $(readlink "$entry_link")"
      rm "$entry_link"
    fi
    echo "removed empty dir: .agents/skills"
    rmdir "$target/.agents/skills" 2>/dev/null || true
    # No skills left here — drop it from the registry.
    "$script_dir/register.sh" -r "$target" || true
  fi
fi

exit "$failed"
