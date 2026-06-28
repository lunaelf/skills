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
#   scripts/link-skill.sh [-f] <target-project-path> <skill-or-package> [<skill-or-package> ...]
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
repo_root="$(cd "$script_dir/.." && pwd)"
src_skills_dir="$repo_root/.agents/skills"
lock_file="$repo_root/skills-lock.json"

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

# --- lockfile queries (jq preferred, python3 fallback) ----------------------

query_lock() {
  # $1: jq filter, $2: python snippet; both read $lock_file.
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1" "$lock_file"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "$2" "$lock_file" "${3:-}"
  else
    echo "error: need jq or python3 to read $lock_file" >&2
    return 2
  fi
}

package_members() {
  # Skill names whose source == $1, in lockfile order.
  local pkg="$1"
  query_lock \
    "$(printf '.skills | to_entries[] | select(.value.source=="%s") | .key' "$pkg")" \
    'import json,sys
d=json.load(open(sys.argv[1]))
[print(n) for n,m in d.get("skills",{}).items() if m.get("source")==sys.argv[2]]' \
    "$pkg"
}

list_packages() {
  query_lock \
    '[.skills[].source] | unique[]' \
    'import json,sys
d=json.load(open(sys.argv[1]))
[print(s) for s in sorted({m.get("source") for m in d.get("skills",{}).values() if m.get("source")})]'
}

# --- linking ----------------------------------------------------------------

link_one() {
  local name="$1"
  local src="$src_skills_dir/$name"
  local dest="$target/.agents/skills/$name"

  if [ ! -d "$src" ]; then
    echo "error: skill not found in store: $name (looked in $src)" >&2
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
  done < <(package_members "$input")

  if [ "${#members[@]}" -gt 0 ]; then
    echo "package '$input' -> ${#members[@]} skills"
    for m in "${members[@]}"; do
      add_skill "$m"
    done
  else
    echo "error: '$input' is neither a skill nor a known package" >&2
    echo "available skills:" >&2
    (cd "$src_skills_dir" && ls -1) | sed 's/^/  - /' >&2
    echo "available packages:" >&2
    list_packages | sed 's/^/  - /' >&2
    failed=1
  fi
done

for name in "${resolved[@]:-}"; do
  [ -n "$name" ] || continue
  link_one "$name" || failed=1
done

if [ "${#resolved[@]}" -gt 0 ]; then
  ensure_entry_link
  # Register the target so scripts/prune-all.sh can find it later. The registry
  # holds machine-specific absolute paths, so it stays local (gitignored).
  registry="$repo_root/links.txt"
  touch "$registry"
  if ! grep -qxF "$target" "$registry"; then
    echo "$target" >> "$registry"
    sort -u "$registry" -o "$registry"
    echo "registered project in links.txt: $target"
  fi
fi

exit "$failed"
