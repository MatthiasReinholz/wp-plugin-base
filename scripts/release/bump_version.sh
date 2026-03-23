#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

VERSION="${1:-}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z [config-path]" >&2
  exit 1
fi

wp_plugin_base_load_config "${2:-}"
wp_plugin_base_require_vars MAIN_PLUGIN_FILE README_FILE

PLUGIN_FILE="$(wp_plugin_base_resolve_path "$MAIN_PLUGIN_FILE")"
README_PATH="$(wp_plugin_base_resolve_path "$README_FILE")"
NOTES_FILE="$(mktemp)"
README_TMP="$(mktemp)"
CHANGELOG_MARKER="== ${CHANGELOG_HEADING} =="

cleanup() {
  rm -f "$NOTES_FILE" "$README_TMP"
}

trap cleanup EXIT

perl -0pi -e "s/^ \\* Version: .*\$/ * Version: $VERSION/m" "$PLUGIN_FILE"
perl -0pi -e "s/^Version: .*\$/Version: $VERSION/m" "$README_PATH"

if grep -q "^ \\* Stable tag: " "$PLUGIN_FILE"; then
  perl -0pi -e "s/^ \\* Stable tag: .*\$/ * Stable tag: $VERSION/m" "$PLUGIN_FILE"
fi

if grep -q "^Stable tag: " "$README_PATH"; then
  perl -0pi -e "s/^Stable tag: .*\$/Stable tag: $VERSION/m" "$README_PATH"
fi

if [ -n "${VERSION_CONSTANT_NAME:-}" ]; then
  perl -0pi -e "s/define\\(\\s*['\\\"]${VERSION_CONSTANT_NAME}['\\\"]\\s*,\\s*['\\\"][^'\\\"]+['\\\"]\\s*\\);/define('${VERSION_CONSTANT_NAME}', '${VERSION}');/m" "$PLUGIN_FILE"
fi

if ! grep -q "^= $VERSION =$" "$README_PATH"; then
  bash "$SCRIPT_DIR/generate_release_notes.sh" "$VERSION" > "$NOTES_FILE"

  if ! grep -q "^${CHANGELOG_MARKER}$" "$README_PATH"; then
    echo "Missing changelog heading in $README_FILE: ${CHANGELOG_MARKER}" >&2
    exit 1
  fi

  while IFS= read -r line; do
    printf '%s\n' "$line" >> "$README_TMP"

    if [ "$line" = "$CHANGELOG_MARKER" ]; then
      printf '\n= %s =\n' "$VERSION" >> "$README_TMP"
      cat "$NOTES_FILE" >> "$README_TMP"
      printf '\n' >> "$README_TMP"
    fi
  done < "$README_PATH"

  mv "$README_TMP" "$README_PATH"
fi

if [ -n "${POT_FILE:-}" ]; then
  POT_PATH="$(wp_plugin_base_resolve_path "$POT_FILE")"

  if [ -f "$POT_PATH" ]; then
    PROJECT_NAME="${POT_PROJECT_NAME:-${PLUGIN_NAME:-Plugin}}"
    perl -0pi -e "s/Project-Id-Version: .*\\\\n/Project-Id-Version: ${PROJECT_NAME} ${VERSION}\\\\n/" "$POT_PATH"
  fi
fi

echo "Updated release metadata to $VERSION."
