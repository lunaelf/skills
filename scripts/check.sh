#!/usr/bin/env bash
#
# check.sh — verify the repo is consistent. Suitable for a pre-commit hook / CI.
#
# Runs:
#   - doctor.sh           store agrees with the three manifests
#   - gen-packages.sh --check   PACKAGES.md is up to date
#
# Exits non-zero if either fails.
#
# Usage:
#   scripts/check.sh
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

rc=0
echo "== doctor =="
"$script_dir/store/doctor.sh" || rc=1
echo
echo "== PACKAGES.md =="
"$script_dir/store/gen-packages.sh" --check || rc=1

echo
if [ "$rc" -eq 0 ]; then
  echo "check: all good"
else
  echo "check: FAILED" >&2
fi
exit "$rc"
