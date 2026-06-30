#!/usr/bin/env bash
#
# lock.sh — shared queries over skills-lock.json and authored.txt.
#
# Sourced by link-skill.sh / gen-packages.sh / doctor.sh. Every function takes
# the file to read as its first argument. JSON is read with jq when available,
# falling back to python3.

# _lock_query <lock> <jq-filter> <py-snippet> [arg]
# py-snippet sees the lock file as sys.argv[1] and arg as sys.argv[2].
_lock_query() {
  local lock="$1" jqf="$2" pys="$3" arg="${4:-}"
  if command -v jq >/dev/null 2>&1; then
    jq -r "$jqf" "$lock"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "$pys" "$lock" "$arg"
  else
    echo "error: need jq or python3 to read $lock" >&2; return 2
  fi
}

# lock_skill_names <lock> -> every installed skill name
lock_skill_names() {
  _lock_query "$1" '.skills | keys[]' \
    'import json,sys; [print(k) for k in json.load(open(sys.argv[1])).get("skills",{})]'
}

# lock_packages <lock> -> distinct package sources
lock_packages() {
  _lock_query "$1" '[.skills[].source] | unique[]' \
    'import json,sys
d=json.load(open(sys.argv[1]))
[print(s) for s in sorted({m.get("source") for m in d.get("skills",{}).values() if m.get("source")})]'
}

# lock_package_members <lock> <pkg> -> skill names whose source == pkg
lock_package_members() {
  _lock_query "$1" \
    "$(printf '.skills | to_entries[] | select(.value.source=="%s") | .key' "$2")" \
    'import json,sys
d=json.load(open(sys.argv[1]))
[print(n) for n,m in d.get("skills",{}).items() if m.get("source")==sys.argv[2]]' \
    "$2"
}

# lock_package_source_type <lock> <pkg> -> sourceType of pkg (or "unknown")
lock_package_source_type() {
  _lock_query "$1" \
    "$(printf '[.skills[] | select(.source=="%s") | .sourceType] | first // "unknown"' "$2")" \
    'import json,sys
d=json.load(open(sys.argv[1]))
ts=[m.get("sourceType","unknown") for m in d.get("skills",{}).values() if m.get("source")==sys.argv[2]]
print(ts[0] if ts else "unknown")' \
    "$2"
}

# read_authored <authored-file> -> skill names, ignoring comments and blanks
read_authored() {
  [ -f "$1" ] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$1" 2>/dev/null || true
}

# resolve_skill_inputs <lock> <store-dir> <input>...
# Each input is a skill dir name in the store, or a package whose members are
# expanded. Echoes the deduped skill names to stdout; per-package info and
# per-unknown errors go to stderr. Returns 1 if any input resolves to nothing.
# Shared by link-skill.sh and unlink-skill.sh.
resolve_skill_inputs() {
  local lock="$1" store="$2"; shift 2
  local input m members n seen=" " rc=0
  for input in "$@"; do
    if [ -d "$store/$input" ]; then
      case "$seen" in *" $input "*) ;; *) seen="$seen$input "; printf '%s\n' "$input" ;; esac
      continue
    fi
    members="$(lock_package_members "$lock" "$input")"
    if [ -n "$members" ]; then
      n=0
      while IFS= read -r m; do
        [ -n "$m" ] || continue
        n=$((n + 1))
        case "$seen" in *" $m "*) ;; *) seen="$seen$m "; printf '%s\n' "$m" ;; esac
      done <<EOF
$members
EOF
      echo "package '$input' -> $n skills" >&2
    else
      {
        echo "error: '$input' is neither a skill nor a known package"
        echo "available skills:"
        (cd "$store" && for d in */; do [ -f "$d/SKILL.md" ] && echo "  - ${d%/}" || :; done)
        echo "available packages:"
        lock_packages "$lock" | sed 's/^/  - /'
      } >&2
      rc=1
    fi
  done
  return "$rc"
}
