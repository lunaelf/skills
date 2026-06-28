#!/usr/bin/env bash
#
# add-external.sh — bring a GitHub-hosted (non-npx) skill into the store.
#
# Clones the repo into the local code tree at <root>/<host>/<owner>/<repo>
# (root = $SKILLS_CODE_ROOT, default ~/Documents/code), symlinks the skill
# into .agents/skills/<name>, records it in external.json (committed), and
# gitignores the machine-specific symlink. Update later with `git pull` in the
# clone, or restore on another machine with scripts/store/sync-external.sh.
#
# Usage:
#   scripts/store/add-external.sh [-f] [-r <ref>] <repo> <skill-path> [<name>]
#
#   <repo>        owner/repo, https URL, or git@ SSH URL
#   <skill-path>  path to the skill dir within the repo (the dir with SKILL.md)
#   <name>        store name (default: basename of <skill-path>)
#
# Options:
#   -r, --ref <ref>   Branch/tag to check out after cloning.
#   -f, --force       Replace an existing symlink at the destination.
#   -h, --help        Show this help.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
# shellcheck source=../lib/external.sh
. "$script_dir/../lib/external.sh"
manifest="$repo_root/external.json"

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

ref=""
force=0
positional=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -r|--ref)   ref="${2:-}"; shift 2 ;;
    -f|--force) force=1; shift ;;
    -h|--help)  usage 0 ;;
    -*)         echo "error: unknown option: $1" >&2; usage 1 >&2 ;;
    *)          positional+=("$1"); shift ;;
  esac
done

if [ "${#positional[@]}" -lt 2 ] || [ "${#positional[@]}" -gt 3 ]; then
  echo "error: need <repo> <skill-path> [<name>]" >&2
  usage 1 >&2
fi

repo="${positional[0]}"
skill_path="${positional[1]}"
name="${positional[2]:-$(basename "$skill_path")}"

url="$(repo_url "$repo")"
clonedir="$(clone_dir_for "$repo")"

if [ ! -d "$clonedir/.git" ]; then
  echo "cloning $url -> $clonedir"
  mkdir -p "$(dirname "$clonedir")"
  git clone "$url" "$clonedir"
else
  echo "using existing clone: $clonedir"
fi

if [ -n "$ref" ]; then
  echo "checking out ref: $ref"
  git -C "$clonedir" checkout "$ref"
fi

src="$clonedir/$skill_path"
if [ ! -f "$src/SKILL.md" ]; then
  echo "error: no SKILL.md at $src" >&2
  echo "       check <skill-path> within the repo" >&2
  exit 1
fi

dest="$repo_root/.agents/skills/$name"
if [ -L "$dest" ]; then
  if [ "$(readlink "$dest")" = "$src" ]; then
    echo "already linked: $name -> $src"
  elif [ "$force" -eq 1 ]; then
    rm "$dest"; ln -s "$src" "$dest"; echo "relinked: $name -> $src"
  else
    echo "error: $dest already links elsewhere (use -f): $(readlink "$dest")" >&2
    exit 1
  fi
elif [ -e "$dest" ]; then
  echo "error: $dest exists and is not a symlink; refusing to clobber" >&2
  exit 1
else
  ln -s "$src" "$dest"
  echo "linked: $name -> $src"
fi

manifest_set "$manifest" "$name" "$url" "$ref" "$skill_path"
echo "recorded in external.json: $name"

ensure_gitignore "$repo_root" "/.agents/skills/$name"
echo "gitignored the symlink: .agents/skills/$name"
