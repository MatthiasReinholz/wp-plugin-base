#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_load_config "${2:-}"
wp_plugin_base_require_vars MAIN_PLUGIN_FILE README_FILE

EXPECTED_TAG="${1:-}"
PLUGIN_FILE="$(wp_plugin_base_resolve_path "$MAIN_PLUGIN_FILE")"
README_PATH="$(wp_plugin_base_resolve_path "$README_FILE")"

if [ ! -f "$PLUGIN_FILE" ] || [ ! -f "$README_PATH" ]; then
  echo "Version files not found." >&2
  exit 1
fi

PLUGIN_VERSION="$(wp_plugin_base_read_header_value "$PLUGIN_FILE" 'Version')"
README_STABLE_TAG="$(wp_plugin_base_read_header_value "$README_PATH" 'Stable tag')"

if [ -z "$PLUGIN_VERSION" ] || [ -z "$README_STABLE_TAG" ]; then
  echo "Unable to read required version values." >&2
  exit 1
fi

REFERENCE_VERSION="$PLUGIN_VERSION"
VALUES=("$PLUGIN_VERSION" "$README_STABLE_TAG")
LABELS=("plugin Version" "readme Stable tag")

if [ -n "${VERSION_CONSTANT_NAME:-}" ]; then
  CONSTANT_VERSION="$(wp_plugin_base_read_define_value "$PLUGIN_FILE" "$VERSION_CONSTANT_NAME")"

  if [ -z "$CONSTANT_VERSION" ]; then
    echo "Unable to read configured version constant: $VERSION_CONSTANT_NAME" >&2
    exit 1
  fi

  VALUES+=("$CONSTANT_VERSION")
  LABELS+=("$VERSION_CONSTANT_NAME")
fi

for index in "${!VALUES[@]}"; do
  if [ "${VALUES[$index]}" != "$REFERENCE_VERSION" ]; then
    echo "Version mismatch detected:" >&2
    for report_index in "${!VALUES[@]}"; do
      printf '  %-18s %s\n' "${LABELS[$report_index]}:" "${VALUES[$report_index]}" >&2
    done
    exit 1
  fi
done

if [ -n "$EXPECTED_TAG" ] && [ "$EXPECTED_TAG" != "$REFERENCE_VERSION" ]; then
  echo "Tag ${EXPECTED_TAG} does not match plugin version ${REFERENCE_VERSION}." >&2
  exit 1
fi

PACKAGE_JSON="$(wp_plugin_base_resolve_path "package.json")"
PACKAGE_LOCK="$(wp_plugin_base_resolve_path "package-lock.json")"
if [ -f "$PACKAGE_JSON" ] || [ -f "$PACKAGE_LOCK" ]; then
  wp_plugin_base_require_commands "JavaScript version checks" jq
fi

if [ -f "$PACKAGE_JSON" ]; then
  if jq -e 'has("version") and (.version | type == "string")' "$PACKAGE_JSON" >/dev/null 2>&1; then
    package_version="$(jq -r '.version' "$PACKAGE_JSON")"
    if [ "$package_version" != "$REFERENCE_VERSION" ]; then
      echo "Version mismatch detected: package.json version ${package_version} does not match ${REFERENCE_VERSION}." >&2
      exit 1
    fi
  fi
fi

if [ -f "$PACKAGE_LOCK" ]; then
  if jq -e 'has("version") and (.version | type == "string")' "$PACKAGE_LOCK" >/dev/null 2>&1; then
    lock_version="$(jq -r '.version' "$PACKAGE_LOCK")"
    if [ "$lock_version" != "$REFERENCE_VERSION" ]; then
      echo "Version mismatch detected: package-lock.json root version ${lock_version} does not match ${REFERENCE_VERSION}." >&2
      exit 1
    fi

    lock_package_root_version="$(jq -r '.packages[""].version // empty' "$PACKAGE_LOCK")"
    if [ -n "$lock_package_root_version" ] && [ "$lock_package_root_version" != "$REFERENCE_VERSION" ]; then
      echo "Version mismatch detected: package-lock.json packages[\"\"].version ${lock_package_root_version} does not match ${REFERENCE_VERSION}." >&2
      exit 1
    fi
  fi
fi

echo "Verified version ${REFERENCE_VERSION}."
