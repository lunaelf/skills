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
# For each resolved skill it creates:
#   <target>/.agents/skills/<name>  ->  <this-repo>/.agents/skills/<name>
# and ensures the Claude Code entry point exists:
#   <target>/.claude/skills         ->  ../.agents/skills
#
# Usage:
#   scripts/project/link-skill.sh [-f] <target-project-path> <skill-or-package> [<skill-or-package> ...]
#
# Options:
#   -f, --force   Replace an existing skill symlink that points elsewhere.
#   -h, --help    Show this help.

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

force=0
positional=()
for arg in "$@"; do
  case "$arg" in
    -f|--force) force=1 ;;
    -h|--help)  usage 0 ;;
    -*)         echo "error: unknown option: $arg" >&2; usage 1 >&2 ;;
    *)          positional+=("$arg") ;;
  esac
done

if [ "${#positional[@]}" -lt 2 ]; then
  echo "error: need a target path and at least one skill or package name" >&2
  usage 1 >&2
fi

# Repo root is the parent of this script's directory.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
src_skills_dir="$repo_root/.agents/skills"
lock_file="$repo_root/skills-lock.json"
# shellcheck source=../lib/lock.sh
. "$script_dir/../lib/lock.sh"

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

# --- linking ----------------------------------------------------------------

link_one() {
  local name="$1"
  local src="$src_skills_dir/$name"
  local dest="$target/.agents/skills/$name"

  if [ ! -d "$src" ]; then
    echo "error: skill not found in store: $name (looked in $src)" >&2
    return 1
  fi

  if [ ! -f "$src/SKILL.md" ]; then
    echo "error: not a skill (no SKILL.md): $name" >&2
    return 1
  fi

  mkdir -p "$target/.agents/skills"

  if [ -L "$dest" ]; then
    local current
    current="$(readlink "$dest")"
    if [ "$current" = "$src" ]; then
      echo "ok (already linked): $name"
      return 0
    fi
    if [ "$force" -eq 1 ]; then
      rm "$dest"
    else
      echo "error: $dest already links to $current (use -f to replace)" >&2
      return 1
    fi
  elif [ -e "$dest" ]; then
    echo "error: $dest exists and is not a symlink; refusing to clobber" >&2
    return 1
  fi

  ln -s "$src" "$dest"
  echo "linked: $name -> $src"
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
  link_one "$name" || failed=1
done

if [ "${#resolved[@]}" -gt 0 ]; then
  ensure_entry_link
  # Record the target so scripts/project/prune-all.sh can find it later.
  "$script_dir/register.sh" "$target" || true
fi

exit "$failed"
