#!/usr/bin/env bash
#
# test.sh — smoke tests for the skill tooling.
#
# Runs the scripts against a throwaway COPY of the repo (so the real
# external.json / PACKAGES.md / links.txt are never touched), a fake $HOME for
# global tests, and a local git "remote" for external tests — no network, no
# mutation of your real environment. Exits non-zero if any check fails.
#
# Usage: scripts/test.sh

set -uo pipefail   # NOT -e: run every check, then report

tests=0 failed=0
t()   { local d="$1"; shift; tests=$((tests+1)); if "$@" >/dev/null 2>&1; then echo "  ok: $d"; else echo "  FAIL: $d"; failed=$((failed+1)); fi; }
tn()  { local d="$1"; shift; tests=$((tests+1)); if "$@" >/dev/null 2>&1; then echo "  FAIL: $d"; failed=$((failed+1)); else echo "  ok: $d"; fi; }
teq() { local d="$1" got="$2" want="$3"; tests=$((tests+1)); if [ "$got" = "$want" ]; then echo "  ok: $d"; else echo "  FAIL: $d (got '$got' want '$want')"; failed=$((failed+1)); fi; }
tsfx(){ local d="$1" val="$2" sfx="$3"; tests=$((tests+1)); case "$val" in *"$sfx") echo "  ok: $d" ;; *) echo "  FAIL: $d (got '$val' want *'$sfx')"; failed=$((failed+1)) ;; esac; }

# All temp dirs live under one base so cleanup is a single rm (mktmp runs in a
# command-substitution subshell, so it can't append to a parent array).
BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
mktmp() { mktemp -d "$BASE/t.XXXXXX"; }

real_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# An isolated working copy of the repo (no .git, no big workspaces).
R="$(mktmp)"
( cd "$real_root" && tar cf - --exclude=.git --exclude=node_modules --exclude='*-workspace' --exclude=links.txt . ) | ( cd "$R" && tar xf - )

LINK="$R/scripts/project/link-skill.sh"
UNLINK="$R/scripts/project/unlink-skill.sh"
PRUNE="$R/scripts/project/prune-skills.sh"
PRUNEALL="$R/scripts/project/prune-all.sh"
. "$R/scripts/lib/lock.sh"
. "$R/scripts/lib/external.sh"

echo "== lib =="
teq "repo_url shorthand"      "$(repo_url owner/repo)"                    "https://github.com/owner/repo.git"
tsfx "clone_dir github https" "$(clone_dir_for https://github.com/o/p.git)" "/github.com/o/p"
tsfx "clone_dir ssh"          "$(clone_dir_for git@github.com:o/p.git)"     "/github.com/o/p"
tsfx "clone_dir gitlab"       "$(clone_dir_for https://gitlab.com/g/p)"     "/gitlab.com/g/p"
teq "lock lists tdd"          "$(lock_skill_names "$R/skills-lock.json" | grep -cx tdd)" "1"
teq "packages include mattpocock" "$(lock_packages "$R/skills-lock.json" | grep -cx 'mattpocock/skills')" "1"
mp_count="$(lock_package_members "$R/skills-lock.json" mattpocock/skills | grep -c .)"
t   "mattpocock has multiple members" test "$mp_count" -ge 2

echo "== link (project) =="
P="$(mktmp)"
"$LINK" "$P" tdd >/dev/null 2>&1
t  "tdd symlinked"        test -L "$P/.agents/skills/tdd"
teq "tdd -> store"        "$(readlink "$P/.agents/skills/tdd")" "$R/.agents/skills/tdd"
t  "entry link made"      test -L "$P/.claude/skills"
teq "entry -> .agents"    "$(readlink "$P/.claude/skills")" "../.agents/skills"
t  "registered in links.txt" grep -qxF "$P" "$R/links.txt"
"$LINK" "$P" mattpocock/skills >/dev/null 2>&1   # package expansion (tdd is a member, so no +1)
teq "package expands to all members" "$(ls "$P/.agents/skills" | grep -c .)" "$mp_count"
tn "non-skill name rejected" "$LINK" "$P" git-commit-workspace

echo "== link (global, fake HOME) =="
GH="$(mktmp)"
HOME="$GH" "$LINK" -g tdd >/dev/null 2>&1
t  "global agents link"   test -L "$GH/.agents/skills/tdd"
teq "global agents target" "$(readlink "$GH/.agents/skills/tdd")" "$R/.agents/skills/tdd"
teq "global claude target" "$(readlink "$GH/.claude/skills/tdd")" "../../.agents/skills/tdd"
tn "global skips links.txt" test -e "$GH/links.txt"
mkdir -p "$GH/.agents/skills/realdir"            # simulate npx -g real install
tn "refuses to clobber real dir" sh -c "HOME='$GH' '$LINK' -g realdir"

echo "== unlink (project) =="
U="$(mktmp)"
"$LINK" "$U" tdd prototype >/dev/null 2>&1
"$UNLINK" -n "$U" tdd >/dev/null 2>&1                 # dry-run removes nothing
t  "dry-run keeps link"   test -L "$U/.agents/skills/tdd"
"$UNLINK" "$U" tdd >/dev/null 2>&1
tn "tdd unlinked"         test -L "$U/.agents/skills/tdd"
t  "prototype kept"       test -L "$U/.agents/skills/prototype"
t  "U registered while linked" grep -qxF "$U" "$R/links.txt"
"$UNLINK" "$U" prototype >/dev/null 2>&1              # last one -> empties dir
tn "entry link cleaned"   test -L "$U/.claude/skills"
tn "empty .agents/skills removed" test -d "$U/.agents/skills"
tn "U deregistered when empty" grep -qxF "$U" "$R/links.txt"
"$UNLINK" "$U" tdd >/dev/null 2>&1                    # idempotent: already gone
t  "unlink idempotent"    true

echo "== register -r =="
RG="$(mktmp)"
: > "$R/links.txt"                                    # RG is the ONLY entry (empty-result case)
"$R/scripts/project/register.sh" "$RG" >/dev/null 2>&1
t  "registered"           grep -qxF "$RG" "$R/links.txt"
"$R/scripts/project/register.sh" -r "$RG" >/dev/null 2>&1
tn "deregistered (sole entry)" grep -qxF "$RG" "$R/links.txt"
teq "links.txt now empty" "$(grep -c . "$R/links.txt")" "0"
tn "no links.txt.tmp left" test -e "$R/links.txt.tmp"

echo "== unlink (global, fake HOME) =="
UG="$(mktmp)"
HOME="$UG" "$LINK" -g tdd >/dev/null 2>&1
mkdir -p "$UG/.agents/skills/foreigndir"             # a real dir (npx -g style)
HOME="$UG" "$UNLINK" -g tdd >/dev/null 2>&1
tn "global agents unlinked" test -L "$UG/.agents/skills/tdd"
tn "global claude unlinked" test -L "$UG/.claude/skills/tdd"
t  "real dir left alone"  test -d "$UG/.agents/skills/foreigndir"

echo "== prune (project) =="
DP="$(mktmp)"; mkdir -p "$DP/.agents/skills" "$DP/.claude"
ln -s "$R/.agents/skills/__gone__" "$DP/.agents/skills/dead"
ln -s "$R/.agents/skills/tdd"      "$DP/.agents/skills/live"
ln -s "../.agents/skills" "$DP/.claude/skills"
"$PRUNE" "$DP" >/dev/null 2>&1
tn "broken link pruned"   test -L "$DP/.agents/skills/dead"
t  "valid link kept"      test -L "$DP/.agents/skills/live"

echo "== prune (global, fake HOME) =="
GP="$(mktmp)"; mkdir -p "$GP/.agents/skills" "$GP/.claude/skills"
ln -s "$R/.agents/skills/__gone__" "$GP/.agents/skills/g1"
ln -s "../../.agents/skills/g1"    "$GP/.claude/skills/g1"
ln -s "/other/store/x"             "$GP/.agents/skills/foreign"
HOME="$GP" "$PRUNE" -g >/dev/null 2>&1
tn "ours broken pruned"   test -L "$GP/.agents/skills/g1"
tn "paired claude pruned" test -L "$GP/.claude/skills/g1"
t  "foreign kept"         test -L "$GP/.agents/skills/foreign"

echo "== prune-all -g =="
AP="$(mktmp)"; mkdir -p "$AP/.agents/skills"
ln -s "$R/.agents/skills/__gone__" "$AP/.agents/skills/dead"
printf '%s\n' "$AP" > "$R/links.txt"
GA="$(mktmp)"; mkdir -p "$GA/.agents/skills" "$GA/.claude/skills"
ln -s "$R/.agents/skills/__gone__" "$GA/.agents/skills/g1"
ln -s "../../.agents/skills/g1"    "$GA/.claude/skills/g1"
HOME="$GA" "$PRUNEALL" -g >/dev/null 2>&1
tn "project link pruned"  test -L "$AP/.agents/skills/dead"
tn "global link pruned"   test -L "$GA/.agents/skills/g1"
tn "emptied project deregistered" grep -qxF "$AP" "$R/links.txt"

echo "== external (fake remote) =="
REM="$(mktmp)/cool"; mkdir -p "$REM/s/foo"
printf -- '---\nname: foo\n---\n' > "$REM/s/foo/SKILL.md"
git -C "$REM" init -q && git -C "$REM" add -A && git -C "$REM" -c user.email=t@t -c user.name=t commit -qm init
export SKILLS_CODE_ROOT="$(mktmp)"
"$R/scripts/store/add-external.sh" "file://$REM" s/foo foo >/dev/null 2>&1
t  "external symlinked"   test -L "$R/.agents/skills/foo"
t  "external in manifest" grep -q '"foo"' "$R/external.json"
t  "external gitignored"  grep -qxF "/.agents/skills/foo" "$R/.gitignore"
"$R/scripts/store/remove-external.sh" foo >/dev/null 2>&1
tn "external symlink gone" test -L "$R/.agents/skills/foo"
tn "external out of manifest" grep -q '"foo"' "$R/external.json"
unset SKILLS_CODE_ROOT

echo "== ui =="
if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  UIP="$(mktmp)"
  UT="test-token-$$"
  UO="$BASE/ui.out"
  SKILLS_UI_TOKEN="$UT" SKILLS_CODE_ROOT="$BASE" HOME="$BASE" \
    python3 "$R/scripts/ui/server.py" --port 0 >"$UO" 2>/dev/null &
  UIPID=$!
  UIURL=""
  for _ in $(seq 1 50); do
    UIURL="$(sed -n 's/^ready: //p' "$UO")"
    [ -n "$UIURL" ] && break
    sleep 0.1
  done
  t   "server ready"        test -n "$UIURL"
  teq "state w/o token 401" "$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "${UIURL}api/state")" "401"
  t   "state with token"    sh -c "curl -sf --max-time 30 -H 'X-Auth-Token: $UT' '${UIURL}api/state' | grep -q '\"doctor\"'"
  t   "link via api"        sh -c "curl -sf --max-time 30 -X POST -H 'X-Auth-Token: $UT' -H 'Content-Type: application/json' -d '{\"target\":\"$UIP\",\"items\":[\"tdd\"]}' '${UIURL}api/link' | grep -q '\"exitCode\": 0'"
  t   "api link created"    test -L "$UIP/.agents/skills/tdd"
  tn  "flag smuggled as name rejected" curl -sf --max-time 30 -X POST -H "X-Auth-Token: $UT" -H 'Content-Type: application/json' -d '{"target":"'"$UIP"'","items":["-g"]}' "${UIURL}api/link"
  tn  "target outside roots rejected"  curl -sf --max-time 30 -X POST -H "X-Auth-Token: $UT" -H 'Content-Type: application/json' -d '{"target":"/etc","items":["tdd"]}' "${UIURL}api/link"
  UTD="$(mktmp)"
  t   "tilde target via api" sh -c "curl -sf --max-time 30 -X POST -H 'X-Auth-Token: $UT' -H 'Content-Type: application/json' -d '{\"paths\":[\"~/${UTD##*/}\"]}' '${UIURL}api/register' | grep -q '\"exitCode\": 0'"
  t   "tilde expanded in links.txt" grep -qxF "$UTD" "$R/links.txt"
  t   "unlink via api"      sh -c "curl -sf --max-time 30 -X POST -H 'X-Auth-Token: $UT' -H 'Content-Type: application/json' -d '{\"target\":\"$UIP\",\"items\":[\"tdd\"]}' '${UIURL}api/unlink' | grep -q '\"exitCode\": 0'"
  tn  "api link removed"    test -L "$UIP/.agents/skills/tdd"
  mkdir -p "$R/.agents/skills/uidesc"   # fixture: YAML block-scalar description
  printf -- '---\nname: uidesc\ndescription: |\n  block line one\n  block line two\n---\n' > "$R/.agents/skills/uidesc/SKILL.md"
  t   "block-scalar description parsed" sh -c "curl -sf --max-time 30 -H 'X-Auth-Token: $UT' '${UIURL}api/state' | grep -q 'block line one block line two'"
  rm -rf "$R/.agents/skills/uidesc"     # keep the copy clean for the consistency checks
  kill "$UIPID" 2>/dev/null
  wait "$UIPID" 2>/dev/null || :
else
  echo "  skip: python3/curl not available"
fi

echo "== consistency =="
rm -f "$R/links.txt"
t "doctor passes on clean copy" "$R/scripts/store/doctor.sh"
t "PACKAGES.md up to date"      "$R/scripts/store/gen-packages.sh" --check

echo
if [ "$failed" -eq 0 ]; then
  echo "all $tests checks passed"
  exit 0
fi
echo "$failed/$tests checks FAILED" >&2
exit 1
