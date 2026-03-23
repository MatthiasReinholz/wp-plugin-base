#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

wp_plugin_base_load_config "${1:-}"
wp_plugin_base_require_vars PLUGIN_SLUG MAIN_PLUGIN_FILE ZIP_FILE

MAIN_PLUGIN_PATH="$(wp_plugin_base_resolve_path "$MAIN_PLUGIN_FILE")"
DISTIGNORE_PATH="$(wp_plugin_base_resolve_path "$DISTIGNORE_FILE")"
DIST_DIR="$ROOT_DIR/dist"
STAGE_ROOT="$DIST_DIR/package"
STAGE_DIR="$STAGE_ROOT/$PLUGIN_SLUG"
ZIP_PATH="$DIST_DIR/$ZIP_FILE"
EXCLUDES_FILE="$(mktemp)"

cleanup() {
  rm -f "$EXCLUDES_FILE"
}

trap cleanup EXIT

if [ ! -f "$MAIN_PLUGIN_PATH" ]; then
  echo "Main plugin file not found: $MAIN_PLUGIN_FILE" >&2
  exit 1
fi

cat <<'EOF' > "$EXCLUDES_FILE"
/.git/
/.github/
/.wp-plugin-base/
/.wordpress-org/
/dist/
/node_modules/
/.wp-plugin-base.env
EOF

if [ -f "$DISTIGNORE_PATH" ]; then
  cat "$DISTIGNORE_PATH" >> "$EXCLUDES_FILE"
fi

wp_plugin_base_csv_to_lines "${PACKAGE_EXCLUDE:-}" >> "$EXCLUDES_FILE"

rm -rf "$STAGE_ROOT" "$ZIP_PATH"
mkdir -p "$STAGE_DIR"

if [ -n "${PACKAGE_INCLUDE:-}" ]; then
  while IFS= read -r include_path; do
    source_path="$(wp_plugin_base_resolve_path "$include_path")"

    if [ ! -e "$source_path" ]; then
      echo "Missing package include path: $include_path" >&2
      exit 1
    fi

    rsync -a --exclude-from="$EXCLUDES_FILE" "$source_path" "$STAGE_DIR/"
  done < <(wp_plugin_base_csv_to_lines "$PACKAGE_INCLUDE")
else
  rsync -a --exclude-from="$EXCLUDES_FILE" "$ROOT_DIR/" "$STAGE_DIR/"
fi

if [ ! -f "$STAGE_DIR/$MAIN_PLUGIN_FILE" ]; then
  echo "Package is missing the main plugin file: $MAIN_PLUGIN_FILE" >&2
  exit 1
fi

if [ -e "$STAGE_DIR/.wp-plugin-base" ] || [ -e "$STAGE_DIR/.github" ] || [ -e "$STAGE_DIR/.wp-plugin-base.env" ]; then
  echo "Package contains foundation or CI-only files." >&2
  exit 1
fi

(cd "$STAGE_ROOT" && zip -qr "$ZIP_PATH" "$PLUGIN_SLUG")

if [ ! -f "$ZIP_PATH" ]; then
  echo "Failed to create package zip." >&2
  exit 1
fi

if command -v unzip >/dev/null 2>&1; then
  if ! unzip -Z1 "$ZIP_PATH" | grep -q "^$PLUGIN_SLUG/$MAIN_PLUGIN_FILE$"; then
    echo "Zip archive does not contain the expected plugin root structure." >&2
    exit 1
  fi
fi

echo "Created $ZIP_PATH"
