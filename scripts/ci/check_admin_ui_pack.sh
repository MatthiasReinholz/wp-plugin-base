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
