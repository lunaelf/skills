#!/usr/bin/env bash
#
# lib-external.sh — shared helpers for GitHub-hosted (non-npx) skills.
#
# Sourced by add-external.sh / sync-external.sh / doctor.sh / gen-packages.sh.
# These skills are cloned to $SKILLS_SRC_DIR and symlinked into the store; the
# symlink is machine-specific (gitignored) while external.json (committed)
# records the repo + path so any machine can restore them.

# Base dir holding clones of external skill repos (override with SKILLS_SRC_DIR).
SKILLS_SRC_DIR="${SKILLS_SRC_DIR:-$HOME/GitHub}"

# normalize_repo <repo> -> prints "<clone-url>\t<clone-dirname>"
# Accepts owner/repo, https URL, or git@ SSH form.
normalize_repo() {
  local repo="$1" url base
  case "$repo" in
    *://* | git@*) url="$repo" ;;                       # any scheme:// or ssh
    */*)           url="https://github.com/$repo.git" ;; # owner/repo shorthand
    *) echo "error: unrecognized repo (want owner/repo or a git URL): $repo" >&2; return 1 ;;
  esac
  base="${repo##*/}"      # last path component
  base="${base%.git}"
  printf '%s\t%s\n' "$url" "$base"
}

clone_dir_for() {
  # clone_dir_for <repo> -> absolute clone path
  local dirname
  dirname="$(normalize_repo "$1" | cut -f2)"
  printf '%s/%s\n' "$SKILLS_SRC_DIR" "$dirname"
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

# ensure_gitignore <repo_root> <pattern> — append pattern under a known header.
ensure_gitignore() {
  local root="$1" pat="$2" gi="$1/.gitignore"
  touch "$gi"
  grep -qxF "$pat" "$gi" && return 0
  if ! grep -qxF "# External skill symlinks (restore via scripts/sync-external.sh)" "$gi"; then
    printf '\n# External skill symlinks (restore via scripts/sync-external.sh)\n' >> "$gi"
  fi
  printf '%s\n' "$pat" >> "$gi"
}
