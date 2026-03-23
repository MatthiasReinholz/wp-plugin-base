#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

RELEASE_TYPE="${1:-}"

if [ -z "$RELEASE_TYPE" ]; then
  echo "Usage: $0 major|minor|patch [config-path]" >&2
  exit 1
fi

wp_plugin_base_load_config "${2:-}"
wp_plugin_base_require_vars MAIN_PLUGIN_FILE

PLUGIN_FILE="$(wp_plugin_base_resolve_path "$MAIN_PLUGIN_FILE")"
CURRENT_VERSION="$(wp_plugin_base_read_header_value "$PLUGIN_FILE" 'Version')"

if ! [[ "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Unable to parse current version from $MAIN_PLUGIN_FILE." >&2
  exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

case "$RELEASE_TYPE" in
  major)
    major=$((major + 1))
    minor=0
    patch=0
    ;;
  minor)
    minor=$((minor + 1))
    patch=0
    ;;
  patch)
    patch=$((patch + 1))
    ;;
  *)
    echo "Unsupported release type: $RELEASE_TYPE" >&2
    exit 1
    ;;
esac

printf '%s.%s.%s\n' "$major" "$minor" "$patch"
