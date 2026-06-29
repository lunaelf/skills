#!/usr/bin/env bash
#
# link-skill.sh — install skills into a project via symlink.
#
# This repo is the central skill store: originals live in .agents/skills/<name>/,
# and skills-lock.json records which package (source) each skill came from.
# Rather than copying, we symlink skills into a target project so that updates
# to the original propagate everywhere, and fixes made in any project flow back
# to the source.
#
# Each argument after the target path is resolved to one or more skills:
#   - if it names a skill in .agents/skills/, that single skill is linked;
#   - otherwise it is treated as a package (a "source" in skills-lock.json, e.g.
#     mattpocock/skills) and every skill belonging to that package is linked.
#     This mirrors `npx skills add <package>` pulling in multiple skills.
#
# Into a project (default), for each resolved skill it creates:
#   <target>/.agents/skills/<name>  ->  <this-repo>/.agents/skills/<name>
# and ensures the Claude Code entry point exists:
#   <target>/.claude/skills         ->  ../.agents/skills
#
# Globally (-g), it installs into the user-level skill dirs the same way
# `npx skills add -g` does — a canonical link plus a per-skill Claude link:
#   ~/.agents/skills/<name>  ->  <this-repo>/.agents/skills/<name>
#   ~/.claude/skills/<name>  ->  ../../.agents/skills/<name>
#
# Usage:
#   scripts/project/link-skill.sh [-f] <target-project-path> <skill-or-package> ...
#   scripts/project/link-skill.sh [-f] -g <skill-or-package> ...
#
# Options:
#   -g, --global  Link into ~/.agents/skills + ~/.claude/skills (no target arg).
#   -f, --force   Replace an existing skill symlink that points elsewhere.
#   -h, --help    Show this help.

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

force=0
global=0
positional=()
for arg in "$@"; do
  case "$arg" in
    -f|--force)  force=1 ;;
    -g|--global) global=1 ;;
    -h|--help)   usage 0 ;;
    -*)          echo "error: unknown option: $arg" >&2; usage 1 >&2 ;;
    *)           positional+=("$arg") ;;
  esac
done

# Repo root is the parent of this script's directory.
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
  # Refuse to link a project into itself.
  if [ "$target" = "$repo_root" ]; then
    echo "error: target is the skills repo itself; nothing to do" >&2
    exit 1
  fi
fi

# --- linking ----------------------------------------------------------------

# make_link <dest> <link-target> — create dest -> link-target, idempotently.
# Sets link_status to "created" or "exists"; returns 1 on an unforced conflict
# or a non-symlink in the way. Honors the global $force.
make_link() {
  local dest="$1" ltarget="$2"
  link_status=""
  mkdir -p "$(dirname "$dest")"

  if [ -L "$dest" ]; then
    if [ "$(readlink "$dest")" = "$ltarget" ]; then
      link_status="exists"; return 0
    fi
    if [ "$force" -eq 1 ]; then
      rm "$dest"
    else
      echo "error: $dest already links to $(readlink "$dest") (use -f to replace)" >&2
      return 1
    fi
  elif [ -e "$dest" ]; then
    echo "error: $dest exists and is not a symlink; refusing to clobber" >&2
    return 1
  fi

  ln -s "$ltarget" "$dest"
  link_status="created"
}

# store_src <name> — echo the store path, validating it's a real skill.
store_src() {
  local name="$1" src="$src_skills_dir/$name"
  if [ ! -d "$src" ]; then
    echo "error: skill not found in store: $name (looked in $src)" >&2
    return 1
  fi
  if [ ! -f "$src/SKILL.md" ]; then
    echo "error: not a skill (no SKILL.md): $name" >&2
    return 1
  fi
  printf '%s\n' "$src"
}

link_one() {
  local name="$1" src
  src="$(store_src "$name")" || return 1
  make_link "$target/.agents/skills/$name" "$src" || return 1
  if [ "$link_status" = exists ]; then
    echo "ok (already linked): $name"
  else
    echo "linked: $name -> $src"
  fi
}

# Global install: ~/.agents/skills/<name> -> store, plus the per-skill Claude
# link ~/.claude/skills/<name> -> ../../.agents/skills/<name> (npx skills -g style).
link_global_one() {
  local name="$1" src
  src="$(store_src "$name")" || return 1
  make_link "$HOME/.agents/skills/$name" "$src" || return 1
  make_link "$HOME/.claude/skills/$name" "../../.agents/skills/$name" || return 1
  echo "linked global: $name"
}

ensure_entry_link() {
  local entry="$target/.claude/skills"

  if [ -L "$entry" ]; then
    return 0   # already a symlink; leave it as-is
  fi
  if [ -e "$entry" ]; then
    echo "warn: $entry exists and is not a symlink; leaving it untouched" >&2
    return 0
  fi

  mkdir -p "$target/.claude"
  ln -s "../.agents/skills" "$entry"
  echo "linked entry: .claude/skills -> ../.agents/skills"
}

# --- resolve inputs to a deduped skill list ---------------------------------

resolved=()
seen=" "   # space-delimited set for dedupe
add_skill() {
  case "$seen" in
    *" $1 "*) return ;;
  esac
  seen="$seen$1 "
  resolved+=("$1")
}

failed=0
for input in "${inputs[@]}"; do
  if [ -d "$src_skills_dir/$input" ]; then
    add_skill "$input"
    continue
  fi

  members=()
  while IFS= read -r m; do
    [ -n "$m" ] && members+=("$m")
  done < <(lock_package_members "$lock_file" "$input")

  if [ "${#members[@]}" -gt 0 ]; then
    echo "package '$input' -> ${#members[@]} skills"
    for m in "${members[@]}"; do
      add_skill "$m"
    done
  else
    echo "error: '$input' is neither a skill nor a known package" >&2
    echo "available skills:" >&2
    (cd "$src_skills_dir" && for d in */; do [ -f "$d/SKILL.md" ] && echo "${d%/}" || :; done) | sed 's/^/  - /' >&2
    echo "available packages:" >&2
    lock_packages "$lock_file" | sed 's/^/  - /' >&2
    failed=1
  fi
done

for name in "${resolved[@]:-}"; do
  [ -n "$name" ] || continue
  if [ "$global" -eq 1 ]; then
    link_global_one "$name" || failed=1
  else
    link_one "$name" || failed=1
  fi
done

if [ "${#resolved[@]}" -gt 0 ] && [ "$global" -eq 0 ]; then
  ensure_entry_link
  # Record the target so scripts/project/prune-all.sh can find it later.
  "$script_dir/register.sh" "$target" || true
fi

exit "$failed"
