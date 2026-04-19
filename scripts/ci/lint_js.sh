#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "JavaScript syntax validation" node

wp_plugin_base_load_config "${1:-}"

while IFS= read -r file; do
  node --check "$file"
done < <(find "$ROOT_DIR" \
  -path "$ROOT_DIR/.git" -prune -o \
  -path "$ROOT_DIR/.github" -prune -o \
  -path "$ROOT_DIR/.wp-plugin-base" -prune -o \
  -path "$ROOT_DIR/.wp-plugin-base-quality-pack" -prune -o \
  -path "$ROOT_DIR/.wp-plugin-base-security-pack" -prune -o \
  -path "$ROOT_DIR/.wp-plugin-base-admin-ui/node_modules" -prune -o \
  -path "$ROOT_DIR/dist" -prune -o \
  -path "$ROOT_DIR/node_modules" -prune -o \
  -name '*.js' -print | sort)
