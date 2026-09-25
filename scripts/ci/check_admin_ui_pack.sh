#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

CONFIG_OVERRIDE="${1:-}"

wp_plugin_base_require_commands "admin UI pack validation" gzip unzip php
wp_plugin_base_load_config "$CONFIG_OVERRIDE"

# DataViews 19 uses public WordPress theme APIs introduced in WordPress 7.1.
# Require honest installation metadata before accepting its built artifacts.
if [ "${ADMIN_UI_STARTER:-basic}" = dataviews ]; then
  for metadata_path in "$MAIN_PLUGIN_FILE" "$README_FILE"; do
    minimum_core="$(wp_plugin_base_read_header_value "$(wp_plugin_base_resolve_path "$metadata_path")" 'Requires at least')"
    if [[ ! "$minimum_core" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] ||
      ! php -r 'exit(version_compare($argv[1], "7.1", ">=") ? 0 : 1);' "$minimum_core"; then
      echo "DataViews starter requires Requires at least: 7.1 or newer in $metadata_path (found: ${minimum_core:-missing})." >&2
      exit 1
    fi
  done
fi

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
# DataViews bundles its public UI implementation and styles. Keep its measured
# opt-in budget separate from the lightweight basic starter.
if [ "${ADMIN_UI_STARTER:-basic}" = dataviews ]; then
  default_script_bytes=1048576
  default_style_bytes=131072
  default_total_bytes=1310720
  default_script_gzip_bytes=262144
  default_style_gzip_bytes=49152
  default_total_gzip_bytes=327680
else
  default_script_bytes=393216
  default_style_bytes=65536
  default_total_bytes=524288
  default_script_gzip_bytes=131072
  default_style_gzip_bytes=32768
  default_total_gzip_bytes=196608
fi
MAX_SCRIPT_BYTES="${WP_PLUGIN_BASE_ADMIN_UI_MAX_SCRIPT_BYTES:-$default_script_bytes}"
MAX_STYLE_BYTES="${WP_PLUGIN_BASE_ADMIN_UI_MAX_STYLE_BYTES:-$default_style_bytes}"
MAX_TOTAL_BYTES="${WP_PLUGIN_BASE_ADMIN_UI_MAX_TOTAL_BYTES:-$default_total_bytes}"
MAX_SCRIPT_GZIP_BYTES="${WP_PLUGIN_BASE_ADMIN_UI_MAX_SCRIPT_GZIP_BYTES:-$default_script_gzip_bytes}"
MAX_STYLE_GZIP_BYTES="${WP_PLUGIN_BASE_ADMIN_UI_MAX_STYLE_GZIP_BYTES:-$default_style_gzip_bytes}"
MAX_TOTAL_GZIP_BYTES="${WP_PLUGIN_BASE_ADMIN_UI_MAX_TOTAL_GZIP_BYTES:-$default_total_gzip_bytes}"

file_size_bytes() {
  wc -c < "$1" | tr -d '[:space:]'
}

assert_asset_size_within_budget() {
  local path="$1"
  local label="$2"
  local budget="$3"
  local gzip_budget="$4"
  local size=""
  local gzip_size=""

  if ! [[ "$budget" =~ ^[1-9][0-9]*$ ]]; then
    echo "${label} size budget must be a positive integer: ${budget}" >&2
    exit 1
  fi

  if ! [[ "$gzip_budget" =~ ^[1-9][0-9]*$ ]]; then
    echo "${label} gzip size budget must be a positive integer: ${gzip_budget}" >&2
    exit 1
  fi

  size="$(file_size_bytes "$path")"
  gzip_size="$(gzip -c "$path" | wc -c | tr -d '[:space:]')"
  echo "${label} size: ${size} bytes (${gzip_size} bytes gzip)."

  if [ "$size" -gt "$budget" ]; then
    echo "${label} exceeds size budget ${budget} bytes: ${size} bytes." >&2
    exit 1
  fi

  if [ "$gzip_size" -gt "$gzip_budget" ]; then
    echo "${label} exceeds gzip size budget ${gzip_budget} bytes: ${gzip_size} bytes." >&2
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

assert_asset_size_within_budget "$INDEX_SCRIPT_PATH" "Admin UI index.js" "$MAX_SCRIPT_BYTES" "$MAX_SCRIPT_GZIP_BYTES"
assert_asset_size_within_budget "$INDEX_STYLE_PATH" "Admin UI style-index.css" "$MAX_STYLE_BYTES" "$MAX_STYLE_GZIP_BYTES"
while IFS= read -r style_file; do
  [ "$style_file" != "$INDEX_STYLE_PATH" ] || continue
  assert_asset_size_within_budget "$style_file" "Admin UI $(basename "$style_file")" "$MAX_STYLE_BYTES" "$MAX_STYLE_GZIP_BYTES"
done < <(find "$ADMIN_UI_ASSETS_DIR" -type f -name '*.css' | sort)


total_asset_bytes="$(
  find "$ADMIN_UI_ASSETS_DIR" -type f -print0 \
    | xargs -0 wc -c \
    | awk 'END { print $1 + 0 }'
)"
echo "Admin UI total asset size: ${total_asset_bytes} bytes."
total_asset_gzip_bytes="$(
  find "$ADMIN_UI_ASSETS_DIR" -type f -print0 \
    | while IFS= read -r -d '' asset_file; do
        gzip -c "$asset_file" | wc -c | tr -d '[:space:]'
        printf '\n'
      done \
    | awk '{ total += $1 } END { print total + 0 }'
)"
echo "Admin UI total asset gzip size: ${total_asset_gzip_bytes} bytes."
if ! [[ "$MAX_TOTAL_BYTES" =~ ^[1-9][0-9]*$ ]]; then
  echo "Admin UI total size budget must be a positive integer: ${MAX_TOTAL_BYTES}" >&2
  exit 1
fi
if ! [[ "$MAX_TOTAL_GZIP_BYTES" =~ ^[1-9][0-9]*$ ]]; then
  echo "Admin UI total gzip size budget must be a positive integer: ${MAX_TOTAL_GZIP_BYTES}" >&2
  exit 1
fi
if [ "$total_asset_bytes" -gt "$MAX_TOTAL_BYTES" ]; then
  echo "Admin UI assets exceed total size budget ${MAX_TOTAL_BYTES} bytes: ${total_asset_bytes} bytes." >&2
  exit 1
fi
if [ "$total_asset_gzip_bytes" -gt "$MAX_TOTAL_GZIP_BYTES" ]; then
  echo "Admin UI assets exceed total gzip size budget ${MAX_TOTAL_GZIP_BYTES} bytes: ${total_asset_gzip_bytes} bytes." >&2
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
done < <(find "$ADMIN_UI_ASSETS_DIR" -type f | sort)

echo "Admin UI pack validation passed."
