#!/usr/bin/env bash
#
# install-hooks.sh — enable the repo's committed git hooks.
#
# Git hooks under .git/hooks aren't version-controlled, so the hooks live in
# scripts/hooks/ instead. This points git at them via core.hooksPath (a local,
# per-clone setting) — run it once after cloning.
#
# Usage:
#   scripts/install-hooks.sh
#
# Options:
#   -h, --help    Show this help.

set -euo pipefail

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage 0 ;;
    *)         echo "error: unknown option: $arg" >&2; usage 1 >&2 ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

chmod +x "$repo_root/scripts/hooks/"* 2>/dev/null || true
git -C "$repo_root" config core.hooksPath scripts/hooks

echo "installed: core.hooksPath -> scripts/hooks"
echo "pre-commit will run scripts/check.sh (bypass with: git commit --no-verify)"
