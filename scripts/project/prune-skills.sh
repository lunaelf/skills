#!/usr/bin/env bash
#
# prune-skills.sh — remove dangling skill symlinks.
#
# When a skill is deleted from the central store (e.g. a package update drops
# it), anything that linked it is left with a broken symlink pointing at a path
# that no longer resolves.
#
# Project mode (default): given a target project, removes broken symlinks under
# <target>/.agents/skills/ (real files/dirs and valid links are left alone). If
# that empties .agents/skills/, the .claude/skills entry link and the empty dir
# are cleaned up too.
#
# Global mode (-g): cleans the user-level dirs that `link-skill.sh -g` writes,
# removing broken ~/.agents/skills/<name> links that point into THIS repo (plus
# their paired ~/.claude/skills/<name> links). Links to other stores / npx -g
# installs are left untouched.
#
# Usage:
#   scripts/project/prune-skills.sh [-n] <target-project-path>
#   scripts/project/prune-skills.sh [-n] -g
#
# Options:
#   -g, --global    Prune the global (~/.agents + ~/.claude) links, not a project.
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

action="removed"
[ "$dry_run" -eq 1 ] && action="would remove"

# Global mode: prune ~/.agents/skills + ~/.claude/skills links into this repo.
prune_global() {
  local script_dir repo_root src_skills_dir agents claude
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "$script_dir/../.." && pwd)"
  src_skills_dir="$repo_root/.agents/skills"
  agents="$HOME/.agents/skills"
  claude="$HOME/.claude/skills"

  local pruned=0 entry name tgt cl
  shopt -s nullglob 2>/dev/null || true

  # Pass 1: broken ~/.agents/skills links whose target is in this repo's store.
  if [ -d "$agents" ]; then
    for entry in "$agents"/*; do
      [ -L "$entry" ] && [ ! -e "$entry" ] || continue
      tgt="$(readlink "$entry")"
      case "$tgt" in "$src_skills_dir"/*) ;; *) continue ;; esac
      name="$(basename "$entry")"
      echo "$action broken global link: ~/.agents/skills/$name -> $tgt"
      [ "$dry_run" -eq 0 ] && rm "$entry"
      pruned=$((pruned + 1))
      # paired Claude link, if it follows our convention
      cl="$claude/$name"
      if [ -L "$cl" ] && [ "$(readlink "$cl")" = "../../.agents/skills/$name" ]; then
        echo "$action paired link: ~/.claude/skills/$name"
        [ "$dry_run" -eq 0 ] && rm "$cl"
      fi
    done
  fi

  # Pass 2: orphaned ~/.claude/skills convention links whose agents entry is gone.
  if [ -d "$claude" ]; then
    for entry in "$claude"/*; do
      name="$(basename "$entry")"
      [ -L "$entry" ] && [ "$(readlink "$entry")" = "../../.agents/skills/$name" ] || continue
      [ ! -e "$entry" ] || continue
      if [ -L "$agents/$name" ] || [ -e "$agents/$name" ]; then continue; fi
      echo "$action orphaned global link: ~/.claude/skills/$name"
      [ "$dry_run" -eq 0 ] && rm "$entry"
      pruned=$((pruned + 1))
    done
  fi

  [ "$pruned" -eq 0 ] && echo "no broken global skill links from this repo"
  return 0
}

if [ "$global" -eq 1 ]; then
  if [ "${#positional[@]}" -ne 0 ]; then
    echo "error: -g takes no target path" >&2
    usage 1 >&2
  fi
  prune_global
  exit 0
fi

# --- project mode -----------------------------------------------------------

if [ "${#positional[@]}" -ne 1 ]; then
  echo "error: need exactly one target project path (or -g)" >&2
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
  if [ -e "$entry" ] || [ -L "$entry" ]; then
    remaining=$((remaining + 1))
  fi
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
