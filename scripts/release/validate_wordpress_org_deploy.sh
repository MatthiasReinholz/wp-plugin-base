#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

VERSION="${1:-}"
CONFIG_OVERRIDE="${2:-}"
SOURCE_OVERRIDE="${3:-}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z [config-path] [source-dir]" >&2
  exit 1
fi

bash "$SCRIPT_DIR/../ci/validate_config.sh" --scope deploy-structure "$CONFIG_OVERRIDE"
wp_plugin_base_load_config "$CONFIG_OVERRIDE"

SOURCE_DIR="${SOURCE_OVERRIDE:-$ROOT_DIR/dist/package/$PLUGIN_SLUG}"
README_BASENAME="$(basename "$README_FILE")"
MAIN_PLUGIN_BASENAME="$(basename "$MAIN_PLUGIN_FILE")"
PACKAGE_PLUGIN_FILE="$SOURCE_DIR/$MAIN_PLUGIN_BASENAME"
PACKAGE_README="$SOURCE_DIR/$README_BASENAME"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "Deploy source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

if [ "$README_BASENAME" != "readme.txt" ] || [ "$README_FILE" != "readme.txt" ]; then
  echo "WordPress.org deploy requires README_FILE=readme.txt at the package root." >&2
  exit 1
fi

if [ ! -f "$PACKAGE_PLUGIN_FILE" ]; then
  echo "Packaged main plugin file not found: $PACKAGE_PLUGIN_FILE" >&2
  exit 1
fi

if [ ! -f "$PACKAGE_README" ]; then
  echo "Packaged readme.txt not found at the package root." >&2
  exit 1
fi

plugin_version="$(wp_plugin_base_read_header_value "$PACKAGE_PLUGIN_FILE" 'Version')"
readme_stable_tag="$(wp_plugin_base_read_header_value "$PACKAGE_README" 'Stable tag')"

if [ "$plugin_version" != "$VERSION" ]; then
  echo "Packaged plugin version ${plugin_version} does not match release version ${VERSION}." >&2
  exit 1
fi

if [ "$readme_stable_tag" != "$VERSION" ]; then
  echo "Packaged readme Stable tag ${readme_stable_tag} does not match release version ${VERSION}." >&2
  exit 1
fi

echo "Validated WordPress.org deploy preflight for $WORDPRESS_ORG_SLUG $VERSION."
