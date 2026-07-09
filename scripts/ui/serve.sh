#!/usr/bin/env bash
#
# serve.sh — start the local web UI for the skill store.
#
# Generates a one-run auth token, starts scripts/ui/server.py bound to
# 127.0.0.1, and opens the browser at the tokened URL. The UI reads state
# from the manifests; every mutation runs the scripts under scripts/.
#
# Usage:
#   scripts/ui/serve.sh [--port <n>] [--no-open]
#
# Options:
#   --port <n>    Port to listen on (default 7331; 0 picks a free port).
#   --no-open     Print the URL instead of opening the browser.
#   -h, --help    Show this help.

set -euo pipefail

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

port=7331
no_open=0
while [ $# -gt 0 ]; do
  case "$1" in
    --port)    shift; port="${1:?error: --port needs a value}" ;;
    --no-open) no_open=1 ;;
    -h|--help) usage 0 ;;
    *)         echo "error: unknown option: $1" >&2; usage 1 >&2 ;;
  esac
  shift
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 1; }

token="$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"

out="$(mktemp)"
pid=""
cleanup() {
  [ -n "$pid" ] && kill "$pid" 2>/dev/null || :
  rm -f "$out"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

SKILLS_UI_TOKEN="$token" python3 "$script_dir/server.py" --port "$port" >"$out" &
pid=$!

# Wait for the ready line (server prints "ready: <url>" once it is listening).
url=""
i=0
while [ "$i" -lt 50 ]; do
  url="$(sed -n 's/^ready: //p' "$out")"
  [ -n "$url" ] && break
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "error: server failed to start" >&2
    exit 1
  fi
  sleep 0.1
  i=$((i+1))
done
if [ -z "$url" ]; then
  echo "error: server did not become ready" >&2
  exit 1
fi

full="${url}#t=${token}"
echo "ui: $full"
echo "    (Ctrl-C 停止)"

if [ "$no_open" -eq 0 ]; then
  case "$(uname)" in
    Darwin) open "$full" ;;
    *)      command -v xdg-open >/dev/null 2>&1 && xdg-open "$full" || : ;;
  esac
fi

wait "$pid" || :
