#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

CONFIG_OVERRIDE="${1:-}"

wp_plugin_base_require_commands "WordPress metadata validation" node
wp_plugin_base_load_config "$CONFIG_OVERRIDE"
wp_plugin_base_require_vars PLUGIN_NAME PLUGIN_SLUG MAIN_PLUGIN_FILE README_FILE PHP_VERSION

PLUGIN_FILE="$(wp_plugin_base_resolve_path "$MAIN_PLUGIN_FILE")"
# shellcheck disable=SC2153
README_PATH="$(wp_plugin_base_resolve_path "$README_FILE")"

header_value() {
  wp_plugin_base_read_header_value "$PLUGIN_FILE" "$1"
}

readme_value() {
  wp_plugin_base_read_header_value "$README_PATH" "$1"
}

require_plugin_header() {
  local header="$1"
  local value

  value="$(header_value "$header")"
  if [ -z "$value" ]; then
    echo "Missing required plugin header: ${header}" >&2
    exit 1
  fi

  printf '%s' "$value"
}

require_readme_header() {
  local header="$1"
  local value

  value="$(readme_value "$header")"
  if [ -z "$value" ]; then
    echo "Missing required readme header: ${header}" >&2
    exit 1
  fi

  printf '%s' "$value"
}

validate_regex() {
  local value="$1"
  local pattern="$2"
  local label="$3"

  if [[ ! "$value" =~ $pattern ]]; then
    echo "Invalid ${label}: ${value}" >&2
    exit 1
  fi
}

validate_https_url() {
  local value="$1"
  local label="$2"
  local scheme='https'
  local separator='://'

  if [[ ! "$value" =~ ^${scheme}${separator}[^[:space:]]+$ ]]; then
    echo "Invalid ${label}: ${value}" >&2
    exit 1
  fi
}

PLUGIN_HEADER_NAME="$(require_plugin_header 'Plugin Name')"
PLUGIN_HEADER_DESCRIPTION="$(require_plugin_header 'Description')"
PLUGIN_HEADER_VERSION="$(require_plugin_header 'Version')"
PLUGIN_HEADER_REQUIRES_AT_LEAST="$(require_plugin_header 'Requires at least')"
PLUGIN_HEADER_REQUIRES_PHP="$(require_plugin_header 'Requires PHP')"
PLUGIN_HEADER_AUTHOR="$(require_plugin_header 'Author')"
PLUGIN_HEADER_LICENSE="$(require_plugin_header 'License')"
PLUGIN_HEADER_TEXT_DOMAIN="$(require_plugin_header 'Text Domain')"

README_TITLE="$(sed -n 's/^=== \(.*\) ===$/\1/p' "$README_PATH" | head -n 1)"
README_CONTRIBUTORS="$(require_readme_header 'Contributors')"
README_REQUIRES_AT_LEAST="$(require_readme_header 'Requires at least')"
README_REQUIRES_PHP="$(require_readme_header 'Requires PHP')"
README_TESTED_UP_TO="$(require_readme_header 'Tested up to')"
README_STABLE_TAG="$(require_readme_header 'Stable tag')"
README_LICENSE="$(require_readme_header 'License')"

if [ "$PLUGIN_HEADER_NAME" != "$PLUGIN_NAME" ]; then
  echo "Plugin header name does not match PLUGIN_NAME: ${PLUGIN_HEADER_NAME}" >&2
  exit 1
fi

if [ "$README_TITLE" != "$PLUGIN_NAME" ]; then
  echo "Readme title does not match PLUGIN_NAME: ${README_TITLE}" >&2
  exit 1
fi

if [ "$PLUGIN_HEADER_REQUIRES_PHP" != "$PHP_VERSION" ]; then
  echo "Plugin header Requires PHP must match PHP_VERSION: ${PLUGIN_HEADER_REQUIRES_PHP}" >&2
  exit 1
fi

if [ "$README_REQUIRES_PHP" != "$PLUGIN_HEADER_REQUIRES_PHP" ]; then
  echo "Readme Requires PHP must match plugin header Requires PHP." >&2
  exit 1
fi

if [ "$README_REQUIRES_AT_LEAST" != "$PLUGIN_HEADER_REQUIRES_AT_LEAST" ]; then
  echo "Readme Requires at least must match plugin header Requires at least." >&2
  exit 1
fi

if [ "$README_STABLE_TAG" != "$PLUGIN_HEADER_VERSION" ]; then
  echo "Readme Stable tag must match plugin Version." >&2
  exit 1
fi

if [ "$PLUGIN_HEADER_TEXT_DOMAIN" != "$PLUGIN_SLUG" ]; then
  echo "Plugin header Text Domain must match PLUGIN_SLUG: ${PLUGIN_HEADER_TEXT_DOMAIN}" >&2
  exit 1
fi

validate_regex "$PLUGIN_HEADER_VERSION" '^[0-9]+\.[0-9]+\.[0-9]+$' 'plugin Version'
validate_regex "$PLUGIN_HEADER_REQUIRES_AT_LEAST" '^[0-9]+\.[0-9]+(\.[0-9]+)?$' 'Requires at least'
validate_regex "$README_TESTED_UP_TO" '^[0-9]+\.[0-9]+(\.[0-9]+)?$' 'Tested up to'
validate_regex "$README_STABLE_TAG" '^[0-9]+\.[0-9]+\.[0-9]+$' 'Stable tag'
validate_regex "$README_CONTRIBUTORS" '^[A-Za-z0-9][A-Za-z0-9-]*(,[[:space:]]*[A-Za-z0-9][A-Za-z0-9-]*)*$' 'Contributors'

PLUGIN_HEADER_DOMAIN_PATH="$(header_value 'Domain Path')"
PLUGIN_HEADER_UPDATE_URI="$(header_value 'Update URI')"
PLUGIN_HEADER_REQUIRES_PLUGINS="$(header_value 'Requires Plugins')"
README_LICENSE_URI="$(readme_value 'License URI')"

if [ -n "${POT_FILE:-}" ] || [ -d "$ROOT_DIR/languages" ]; then
  if [ -z "$PLUGIN_HEADER_DOMAIN_PATH" ]; then
    echo "Domain Path is required when translation files are present." >&2
    exit 1
  fi
fi

if [ -n "$PLUGIN_HEADER_DOMAIN_PATH" ]; then
  validate_regex "$PLUGIN_HEADER_DOMAIN_PATH" '^/[A-Za-z0-9._/-]+$' 'Domain Path'
fi

if [ -n "$PLUGIN_HEADER_UPDATE_URI" ] && [ "$PLUGIN_HEADER_UPDATE_URI" != "false" ]; then
  validate_https_url "$PLUGIN_HEADER_UPDATE_URI" 'Update URI'
fi

if [ -n "$PLUGIN_HEADER_REQUIRES_PLUGINS" ]; then
  while IFS= read -r slug; do
    validate_regex "$slug" '^[a-z0-9][a-z0-9-]*$' 'Requires Plugins slug'
  done < <(wp_plugin_base_csv_to_lines "$PLUGIN_HEADER_REQUIRES_PLUGINS")
fi

if [ -n "$README_LICENSE_URI" ]; then
  validate_https_url "$README_LICENSE_URI" 'License URI'
fi

if [ -z "$PLUGIN_HEADER_DESCRIPTION" ] || [ -z "$PLUGIN_HEADER_AUTHOR" ] || [ -z "$PLUGIN_HEADER_LICENSE" ] || [ -z "$README_LICENSE" ]; then
  echo "Plugin and readme metadata must not be empty." >&2
  exit 1
fi

PACKAGE_JSON_PATH="$ROOT_DIR/package.json"
if [ -f "$PACKAGE_JSON_PATH" ]; then
  has_wp_plugin="$(
    node - <<'EOF' "$PACKAGE_JSON_PATH"
const fs = require("node:fs");
const packageJsonPath = process.argv[2];
const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
process.stdout.write(packageJson.wpPlugin ? "true" : "false");
EOF
  )"

  if [ "$has_wp_plugin" = "true" ]; then
    BUILD_BOOTSTRAP="$ROOT_DIR/build/build.php"

    if [ ! -f "$BUILD_BOOTSTRAP" ]; then
      echo "package.json declares wpPlugin, but build/build.php is missing." >&2
      exit 1
    fi

    if ! grep -Eq "require(_once)?[[:space:]]+__DIR__[[:space:]]*\\.[[:space:]]*['\"]/build/build\\.php['\"]" "$PLUGIN_FILE"; then
      echo "package.json declares wpPlugin, but the main plugin file does not require build/build.php." >&2
      exit 1
    fi
  fi
fi

echo "Validated WordPress plugin headers and readme metadata."
