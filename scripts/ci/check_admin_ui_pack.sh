#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

CONFIG_OVERRIDE="${1:-}"

wp_plugin_base_require_commands "admin UI pack validation" unzip
wp_plugin_base_load_config "$CONFIG_OVERRIDE"

if [ -z "${BUILD_SCRIPT:-}" ]; then
  echo "ADMIN_UI_PACK_ENABLED=true requires BUILD_SCRIPT to point at the seeded admin UI build wrapper." >&2
  exit 1
fi

BUILD_SCRIPT_PATH="$(wp_plugin_base_resolve_path "$BUILD_SCRIPT")"
INDEX_SCRIPT_PATH="$(wp_plugin_base_resolve_path "assets/admin-ui/index.js")"
INDEX_ASSET_PATH="$(wp_plugin_base_resolve_path "assets/admin-ui/index.asset.php")"
INDEX_STYLE_PATH="$(wp_plugin_base_resolve_path "assets/admin-ui/style-index.css")"
ADMIN_UI_ASSETS_DIR="$(wp_plugin_base_resolve_path "assets/admin-ui")"
ZIP_PATH="$(wp_plugin_base_resolve_path "dist/$ZIP_FILE")"
MAX_SCRIPT_BYTES="${WP_PLUGIN_BASE_ADMIN_UI_MAX_SCRIPT_BYTES:-393216}"
MAX_STYLE_BYTES="${WP_PLUGIN_BASE_ADMIN_UI_MAX_STYLE_BYTES:-65536}"
MAX_TOTAL_BYTES="${WP_PLUGIN_BASE_ADMIN_UI_MAX_TOTAL_BYTES:-524288}"

file_size_bytes() {
  wc -c < "$1" | tr -d '[:space:]'
}

assert_asset_size_within_budget() {
  local path="$1"
  local label="$2"
  local budget="$3"
  local size=""
  local gzip_size=""

  if ! [[ "$budget" =~ ^[1-9][0-9]*$ ]]; then
    echo "${label} size budget must be a positive integer: ${budget}" >&2
    exit 1
  fi

  size="$(file_size_bytes "$path")"
  if command -v gzip >/dev/null 2>&1; then
    gzip_size="$(gzip -c "$path" | wc -c | tr -d '[:space:]')"
    echo "${label} size: ${size} bytes (${gzip_size} bytes gzip)."
  else
    echo "${label} size: ${size} bytes."
  fi

  if [ "$size" -gt "$budget" ]; then
    echo "${label} exceeds size budget ${budget} bytes: ${size} bytes." >&2
    exit 1
  fi
}

if [ ! -f "$BUILD_SCRIPT_PATH" ]; then
  echo "Configured BUILD_SCRIPT does not exist: $BUILD_SCRIPT" >&2
  exit 1
fi

if [ ! -f "$INDEX_SCRIPT_PATH" ] || [ ! -f "$INDEX_ASSET_PATH" ] || [ ! -f "$INDEX_STYLE_PATH" ]; then
  echo "Admin UI build outputs are missing. Expected assets/admin-ui/index.js, assets/admin-ui/index.asset.php, and assets/admin-ui/style-index.css after BUILD_SCRIPT runs." >&2
  exit 1
fi

if [ ! -f "$ZIP_PATH" ]; then
  echo "Expected packaged zip is missing: dist/$ZIP_FILE" >&2
  exit 1
fi

assert_asset_size_within_budget "$INDEX_SCRIPT_PATH" "Admin UI index.js" "$MAX_SCRIPT_BYTES"
assert_asset_size_within_budget "$INDEX_STYLE_PATH" "Admin UI style-index.css" "$MAX_STYLE_BYTES"

total_asset_bytes="$(
  find "$ADMIN_UI_ASSETS_DIR" -maxdepth 1 -type f -print0 \
    | xargs -0 wc -c \
    | awk 'END { print $1 + 0 }'
)"
echo "Admin UI total asset size: ${total_asset_bytes} bytes."
if ! [[ "$MAX_TOTAL_BYTES" =~ ^[1-9][0-9]*$ ]]; then
  echo "Admin UI total size budget must be a positive integer: ${MAX_TOTAL_BYTES}" >&2
  exit 1
fi
if [ "$total_asset_bytes" -gt "$MAX_TOTAL_BYTES" ]; then
  echo "Admin UI assets exceed total size budget ${MAX_TOTAL_BYTES} bytes: ${total_asset_bytes} bytes." >&2
  exit 1
fi

zip_listing="$(unzip -Z1 "$ZIP_PATH")"
if ! grep -Fq "$PLUGIN_SLUG/assets/admin-ui/index.js" <<<"$zip_listing"; then
  echo "Admin UI package zip does not contain assets/admin-ui/index.js." >&2
  exit 1
fi

if ! grep -Fq "$PLUGIN_SLUG/assets/admin-ui/index.asset.php" <<<"$zip_listing"; then
  echo "Admin UI package zip does not contain assets/admin-ui/index.asset.php." >&2
  exit 1
fi

if ! grep -Fq "$PLUGIN_SLUG/assets/admin-ui/style-index.css" <<<"$zip_listing"; then
  echo "Admin UI package zip does not contain assets/admin-ui/style-index.css." >&2
  exit 1
fi

if grep -Fq "$PLUGIN_SLUG/.wp-plugin-base-admin-ui/" <<<"$zip_listing"; then
  echo "Admin UI tooling directory leaked into the packaged zip." >&2
  exit 1
fi

while IFS= read -r asset_file; do
  [ -n "$asset_file" ] || continue
  asset_relative_path="${asset_file#"$ROOT_DIR"/}"

  if ! grep -Fq "$PLUGIN_SLUG/$asset_relative_path" <<<"$zip_listing"; then
    echo "Admin UI package zip is missing built asset $asset_relative_path." >&2
    exit 1
  fi
done < <(find "$ADMIN_UI_ASSETS_DIR" -maxdepth 1 -type f | sort)

echo "Admin UI pack validation passed."
