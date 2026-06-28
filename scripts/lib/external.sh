#!/usr/bin/env bash
#
# external.sh — shared helpers for GitHub-hosted (non-npx) skills.
#
# Sourced by add-external.sh / sync-external.sh / remove-external.sh /
# doctor.sh / gen-packages.sh.
# These skills are cloned into the local code tree (see SKILLS_CODE_ROOT) and
# symlinked into the store; the symlink is machine-specific (gitignored) while
# external.json (committed) records the repo + path so any machine can restore.

# Root of the local code tree, laid out as <root>/<host>/<owner>/<repo>
# (the ghq / go-style convention). Override with SKILLS_CODE_ROOT.
SKILLS_CODE_ROOT="${SKILLS_CODE_ROOT:-$HOME/Documents/code}"

# parse_repo <repo> -> prints "<clone-url>\t<host>\t<owner>\t<repo>"
# Accepts owner/repo shorthand, https URL, or git@ SSH form. For URL schemes
# without a host/owner (e.g. file://), host=local owner=_ as a fallback.
parse_repo() {
  local repo="$1" url host path owner name rest
  case "$repo" in
    git@*)                                  # git@host:owner/repo(.git)
      url="$repo"
      host="${repo#git@}"; host="${host%%:*}"
      path="${repo#*:}"
      ;;
    ssh://*|http://*|https://*|git://*)      # scheme://[user@]host/owner/repo
      url="$repo"
      rest="${repo#*://}"; rest="${rest#*@}"
      host="${rest%%/*}"
      path="${rest#*/}"
      ;;
    *://*)                                   # other schemes (file://, ...)
      url="$repo"; host="local"; path="" ;;
    */*)                                     # owner/repo shorthand -> github.com
      url="https://github.com/$repo.git"; host="github.com"; path="$repo" ;;
    *) echo "error: unrecognized repo (want owner/repo or a git URL): $repo" >&2; return 1 ;;
  esac

  path="${path%.git}"; path="${path%/}"
  if [ -n "$path" ]; then
    owner="${path%%/*}"
    name="${path##*/}"
  fi
  [ -n "${owner:-}" ] || owner="_"
  if [ -z "${name:-}" ]; then name="${repo##*/}"; name="${name%.git}"; fi
  printf '%s\t%s\t%s\t%s\n' "$url" "$host" "$owner" "$name"
}

# repo_url <repo> -> clone URL only
repo_url() { parse_repo "$1" | cut -f1; }

# clone_dir_for <repo> -> absolute clone path <root>/<host>/<owner>/<repo>
clone_dir_for() {
  local f host owner name
  f="$(parse_repo "$1")" || return 1
  host="$(printf '%s' "$f" | cut -f2)"
  owner="$(printf '%s' "$f" | cut -f3)"
  name="$(printf '%s' "$f" | cut -f4)"
  printf '%s/%s/%s/%s\n' "$SKILLS_CODE_ROOT" "$host" "$owner" "$name"
}

# external_names <manifest> -> skill names, one per line
external_names() {
  local m="$1"
  [ -f "$m" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r '.skills | keys[]' "$m"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; [print(k) for k in json.load(open(sys.argv[1])).get("skills",{})]' "$m"
  else
    echo "error: need jq or python3 to read $m" >&2; return 2
  fi
}

# external_rows <manifest> -> "name<TAB>repo<TAB>ref<TAB>skillPath" per skill
external_rows() {
  local m="$1"
  [ -f "$m" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r '.skills | to_entries[] | [.key, .value.repo, (.value.ref // ""), .value.skillPath] | @tsv' "$m"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
for n,m in d.get("skills",{}).items():
    print("\t".join([n, m.get("repo",""), m.get("ref","") or "", m.get("skillPath","")]))' "$m"
  else
    echo "error: need jq or python3 to read $m" >&2; return 2
  fi
}

# manifest_set <manifest> <name> <repo-url> <ref> <skillPath>
manifest_set() {
  local m="$1" n="$2" r="$3" ref="$4" p="$5" tmp
  tmp="$(mktemp)"
  if command -v jq >/dev/null 2>&1; then
    jq --arg n "$n" --arg r "$r" --arg ref "$ref" --arg p "$p" \
      '(.version //= 1) | (.skills //= {}) | .skills[$n] = {repo:$r, ref:$ref, skillPath:$p}' \
      "$m" > "$tmp" && mv "$tmp" "$m"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$m" "$n" "$r" "$ref" "$p" <<'PY' && true
import json,sys
f,n,r,ref,p = sys.argv[1:6]
try:
    d = json.load(open(f))
except Exception:
    d = {}
d.setdefault("version", 1); d.setdefault("skills", {})
d["skills"][n] = {"repo": r, "ref": ref, "skillPath": p}
with open(f, "w") as fh:
    json.dump(d, fh, indent=2, ensure_ascii=False); fh.write("\n")
PY
  else
    echo "error: need jq or python3 to write $m" >&2; rm -f "$tmp"; return 2
  fi
}

# manifest_remove <manifest> <name>
manifest_remove() {
  local m="$1" n="$2" tmp
  [ -f "$m" ] || return 0
  tmp="$(mktemp)"
  if command -v jq >/dev/null 2>&1; then
    jq --arg n "$n" 'del(.skills[$n])' "$m" > "$tmp" && mv "$tmp" "$m"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$m" "$n" <<'PY'
import json,sys
f,n = sys.argv[1:3]
d = json.load(open(f))
d.get("skills",{}).pop(n, None)
with open(f,"w") as fh:
    json.dump(d, fh, indent=2, ensure_ascii=False); fh.write("\n")
PY
  fi
}

_GITIGNORE_EXTERNAL_HEADER="# External skill symlinks (restore via scripts/store/sync-external.sh)"

# ensure_gitignore <repo_root> <pattern> — append pattern under a known header.
ensure_gitignore() {
  local pat="$2" gi="$1/.gitignore"
  touch "$gi"
  grep -qxF "$pat" "$gi" && return 0
  grep -qxF "$_GITIGNORE_EXTERNAL_HEADER" "$gi" || printf '\n%s\n' "$_GITIGNORE_EXTERNAL_HEADER" >> "$gi"
  printf '%s\n' "$pat" >> "$gi"
}

# gitignore_remove <repo_root> <pattern> — drop pattern; drop the header too if
# no external entries remain.
gitignore_remove() {
  local pat="$2" gi="$1/.gitignore" tmp
  [ -f "$gi" ] || return 0
  tmp="$(mktemp)"
  grep -vxF "$pat" "$gi" > "$tmp" || true
  if ! grep -qE '^/\.agents/skills/' "$tmp"; then
    grep -vxF "$_GITIGNORE_EXTERNAL_HEADER" "$tmp" > "$tmp.2" || true
    mv "$tmp.2" "$tmp"
  fi
  mv "$tmp" "$gi"
}
