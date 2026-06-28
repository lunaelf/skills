#!/usr/bin/env bash
#
# gen-packages.sh — regenerate PACKAGES.md from skills-lock.json.
#
# skills-lock.json is the source of truth for which package (source) every
# installed skill came from. This script rolls that up into a browsable
# PACKAGES.md so you can see, at a glance, which packages are installed and
# which skills each one brought in.
#
# Run it after `npx skills add <package>` (or any change to the lockfile):
#   scripts/store/gen-packages.sh
#
# Options:
#   --check       Don't write; exit non-zero if PACKAGES.md is out of date.
#   -h, --help    Show this help.

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

check=0
for arg in "$@"; do
  case "$arg" in
    --check)    check=1 ;;
    -h|--help)  usage 0 ;;
    *)          echo "error: unknown option: $arg" >&2; usage 1 >&2 ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
lock_file="$repo_root/skills-lock.json"
out_file="$repo_root/PACKAGES.md"
src_skills_dir="$repo_root/.agents/skills"
authored_file="$repo_root/authored.txt"
external_file="$repo_root/external.json"
# shellcheck source=../lib/external.sh
. "$script_dir/../lib/external.sh"
# shellcheck source=../lib/lock.sh
. "$script_dir/../lib/lock.sh"

if [ ! -f "$lock_file" ]; then
  echo "error: lockfile not found: $lock_file" >&2
  exit 1
fi

# --- render markdown --------------------------------------------------------

render() {
  printf '# 已安装的 package\n\n'
  printf '> 本文件由 `scripts/store/gen-packages.sh` 从 `skills-lock.json` 生成，请勿手动编辑。\n\n'

  local pkgs=()
  while IFS= read -r p; do
    [ -n "$p" ] && pkgs+=("$p")
  done < <(lock_packages "$lock_file")

  if [ "${#pkgs[@]}" -eq 0 ]; then
    printf '_目前没有已安装的 package。_\n'
  else
    printf '共 %d 个 package。\n' "${#pkgs[@]}"
    for pkg in "${pkgs[@]}"; do
      local stype members count
      stype="$(lock_package_source_type "$lock_file" "$pkg")"
      members=()
      while IFS= read -r m; do
        [ -n "$m" ] && members+=("$m")
      done < <(lock_package_members "$lock_file" "$pkg")
      count="${#members[@]}"

      printf '\n## %s\n\n' "$pkg"
      printf -- '- 来源类型：%s\n' "$stype"
      printf -- '- skill（%d 个）：\n' "$count"
      for m in "${members[@]}"; do
        printf '  - `%s`\n' "$m"
      done
    done
  fi

  # Self-authored skills (listed in authored.txt, present in the store).
  local authored=()
  while IFS= read -r a; do
    [ -n "$a" ] && [ -d "$src_skills_dir/$a" ] && authored+=("$a")
  done < <(read_authored "$authored_file")

  if [ "${#authored[@]}" -gt 0 ]; then
    printf '\n## 自己写的 skill（%d 个）\n\n' "${#authored[@]}"
    printf -- '- 不来自 package，由本仓库维护。\n\n'
    for a in "${authored[@]}"; do
      printf '  - `%s`\n' "$a"
    done
  fi

  # External GitHub skills (from external.json).
  local ext_rows ecount
  ext_rows="$(external_rows "$external_file" 2>/dev/null || true)"
  ecount="$(printf '%s' "$ext_rows" | grep -c . || true)"
  if [ "$ecount" -gt 0 ]; then
    printf '\n## 外部 GitHub skill（%d 个）\n\n' "$ecount"
    printf -- '- 来自 GitHub 仓库（非 npx），符号链接进来；用 scripts/store/sync-external.sh 还原/更新。\n\n'
    # Split on tab manually: `read` with IFS=tab collapses the empty ref field.
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      name="${row%%$'\t'*}"; row="${row#*$'\t'}"
      repo="${row%%$'\t'*}"; row="${row#*$'\t'}"
      ref="${row%%$'\t'*}";  path="${row#*$'\t'}"
      if [ -n "$ref" ]; then
        printf '  - `%s` — %s @ `%s`（`%s`）\n' "$name" "$repo" "$ref" "$path"
      else
        printf '  - `%s` — %s（`%s`）\n' "$name" "$repo" "$path"
      fi
    done <<EOF
$ext_rows
EOF
  fi
}

new_content="$(render)"

if [ "$check" -eq 1 ]; then
  if [ -f "$out_file" ] && [ "$new_content" = "$(cat "$out_file")" ]; then
    echo "PACKAGES.md is up to date"
    exit 0
  fi
  echo "error: PACKAGES.md is out of date; run scripts/store/gen-packages.sh" >&2
  exit 1
fi

printf '%s\n' "$new_content" > "$out_file"
echo "wrote $out_file"
