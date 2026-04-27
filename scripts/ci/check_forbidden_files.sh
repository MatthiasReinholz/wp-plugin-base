#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

CONFIG_OVERRIDE="${1:-}"

if [ -n "$CONFIG_OVERRIDE" ] || [ -f "$SCRIPT_DIR/../../.wp-plugin-base.env" ]; then
  wp_plugin_base_load_config "$CONFIG_OVERRIDE"
else
  ROOT_DIR="${WP_PLUGIN_BASE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
fi

forbidden_files=()
while IFS= read -r path; do
  forbidden_files+=("$path")
done < <(find "$ROOT_DIR" \
  -path "$ROOT_DIR/.git" -prune -o \
  -type d -name 'node_modules' -prune -o \
  -path "$ROOT_DIR/dist" -prune -o \
  -type f \( \
    -name '.DS_Store' -o \
    -name 'Thumbs.db' -o \
    -name 'Desktop.ini' -o \
    -name 'npm-debug.log' -o \
    -name 'npm-debug.log.*' -o \
    -name 'yarn-error.log' -o \
    -name 'yarn-error.log.*' \
  \) -print | sort)

for dir in "$ROOT_DIR/.idea" "$ROOT_DIR/.vscode"; do
  if [ -d "$dir" ]; then
    forbidden_files+=("$dir")
  fi
done

if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r tracked_path; do
    [ -n "$tracked_path" ] || continue
    forbidden_files+=("$ROOT_DIR/$tracked_path")
  done < <(
    git -C "$ROOT_DIR" ls-files -- \
      '.wp-plugin-base-quality-pack/vendor/*' \
      '.wp-plugin-base-security-pack/vendor/*'
  )
fi

if [ "${#forbidden_files[@]}" -eq 0 ]; then
  echo "Forbidden file policy passed."
  exit 0
fi

echo "Forbidden files or directories are present and must not be committed:" >&2
echo "Generated quality/security pack vendor files are local tooling state; remove them from git if listed below." >&2
printf '  %s\n' "${forbidden_files[@]}" >&2
exit 1
