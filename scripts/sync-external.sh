#!/usr/bin/env bash
#
# sync-external.sh — restore/update external skills from external.json.
#
# For every skill recorded in external.json: ensure its repo is cloned into the
# local code tree (see SKILLS_CODE_ROOT), pull the latest (unless --no-pull),
# and (re)create the
# symlink into .agents/skills/<name>. Run this on a fresh machine to restore
# external skills, or any time to update them all at once.
#
# Usage:
#   scripts/sync-external.sh [--no-pull]
#
# Options:
#   --no-pull     Clone if missing and fix symlinks, but don't pull updates.
#   -h, --help    Show this help.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=lib-external.sh
. "$script_dir/lib-external.sh"
manifest="$repo_root/external.json"

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

no_pull=0
for arg in "$@"; do
  case "$arg" in
    --no-pull) no_pull=1 ;;
    -h|--help) usage 0 ;;
    *)         echo "error: unknown option: $arg" >&2; usage 1 >&2 ;;
  esac
done

if [ ! -f "$manifest" ]; then
  echo "no external.json; nothing to sync"
  exit 0
fi

count=0
failed=0
# Split on tab manually: `read` with IFS=tab collapses the empty ref field.
while IFS= read -r row; do
  [ -n "$row" ] || continue
  name="${row%%$'\t'*}";        row="${row#*$'\t'}"
  repo="${row%%$'\t'*}";        row="${row#*$'\t'}"
  ref="${row%%$'\t'*}";         skill_path="${row#*$'\t'}"
  count=$((count + 1))
  echo "=== $name ($repo) ==="

  clonedir="$(clone_dir_for "$repo")"
  url="$(repo_url "$repo")"

  if [ ! -d "$clonedir/.git" ]; then
    echo "cloning $url -> $clonedir"
    mkdir -p "$(dirname "$clonedir")"
    if ! git clone "$url" "$clonedir"; then
      echo "warn: clone failed for $name" >&2; failed=1; continue
    fi
  fi

  if [ -n "$ref" ]; then
    git -C "$clonedir" checkout "$ref" || { echo "warn: checkout $ref failed for $name" >&2; failed=1; }
  fi
  if [ "$no_pull" -eq 0 ]; then
    git -C "$clonedir" pull --ff-only || echo "warn: pull failed for $name (continuing)" >&2
  fi

  src="$clonedir/$skill_path"
  if [ ! -f "$src/SKILL.md" ]; then
    echo "warn: no SKILL.md at $src — skipping link" >&2; failed=1; continue
  fi

  dest="$repo_root/.agents/skills/$name"
  if [ -L "$dest" ]; then
    if [ "$(readlink "$dest")" = "$src" ]; then
      echo "ok: $name already linked"
    else
      rm "$dest"; ln -s "$src" "$dest"; echo "relinked: $name"
    fi
  elif [ -e "$dest" ]; then
    echo "warn: $dest exists and is not a symlink; leaving it" >&2; failed=1
  else
    ln -s "$src" "$dest"; echo "linked: $name -> $src"
  fi

  ensure_gitignore "$repo_root" "/.agents/skills/$name"
done < <(external_rows "$manifest")

echo
echo "synced $count external skill(s)"
exit "$failed"
