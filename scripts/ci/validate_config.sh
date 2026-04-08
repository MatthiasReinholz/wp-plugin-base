#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

CONFIG_SCOPE="project"
CONFIG_OVERRIDE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --scope)
      if [ "$#" -lt 2 ]; then
        echo "--scope requires a value." >&2
        exit 1
      fi
      CONFIG_SCOPE="$2"
      shift 2
      ;;
    --scope=*)
      CONFIG_SCOPE="${1#*=}"
      shift
      ;;
    *)
      CONFIG_OVERRIDE="$1"
      shift
      ;;
  esac
done

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

validate_regex() {
  local value="$1"
  local pattern="$2"
  local label="$3"

  if [[ ! "$value" =~ $pattern ]]; then
    echo "Invalid ${label}: ${value}" >&2
    exit 1
  fi
}

validate_file() {
  local relative_path="$1"
  local label="$2"
  local resolved_path

  resolved_path="$(wp_plugin_base_resolve_path "$relative_path")"
  wp_plugin_base_assert_path_within_root "$resolved_path" "$label"
  if [ ! -f "$resolved_path" ]; then
    echo "${label} not found: ${relative_path}" >&2
    exit 1
  fi
}

validate_optional_paths() {
  local raw_paths="$1"
  local label="$2"
  local path
  local resolved_path

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    resolved_path="$(wp_plugin_base_resolve_path "$path")"
    wp_plugin_base_assert_path_within_root "$resolved_path" "$label"
    if [ ! -e "$resolved_path" ]; then
      echo "${label} path not found: ${path}" >&2
      exit 1
    fi
  done < <(wp_plugin_base_csv_to_lines "$raw_paths")
}

case "$CONFIG_SCOPE" in
  sync|foundation)
    wp_plugin_base_require_vars FOUNDATION_REPOSITORY FOUNDATION_VERSION PRODUCTION_ENVIRONMENT
    ;;
  project|ci|readiness|release)
    wp_plugin_base_require_vars FOUNDATION_REPOSITORY FOUNDATION_VERSION PLUGIN_NAME PLUGIN_SLUG MAIN_PLUGIN_FILE README_FILE ZIP_FILE PHP_VERSION NODE_VERSION PRODUCTION_ENVIRONMENT
    ;;
  deploy-structure)
    wp_plugin_base_require_vars FOUNDATION_REPOSITORY FOUNDATION_VERSION PLUGIN_NAME PLUGIN_SLUG MAIN_PLUGIN_FILE README_FILE ZIP_FILE PHP_VERSION NODE_VERSION PRODUCTION_ENVIRONMENT WORDPRESS_ORG_SLUG
    ;;
  deploy)
    wp_plugin_base_require_vars FOUNDATION_REPOSITORY FOUNDATION_VERSION PLUGIN_NAME PLUGIN_SLUG MAIN_PLUGIN_FILE README_FILE ZIP_FILE PHP_VERSION NODE_VERSION PRODUCTION_ENVIRONMENT WORDPRESS_ORG_SLUG SVN_USERNAME SVN_PASSWORD
    ;;
  *)
    echo "Unsupported config validation scope: ${CONFIG_SCOPE}" >&2
    exit 1
    ;;
esac

validate_regex "$FOUNDATION_REPOSITORY" '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' 'FOUNDATION_REPOSITORY'
validate_regex "$FOUNDATION_VERSION" '^v[0-9]+\.[0-9]+\.[0-9]+$' 'FOUNDATION_VERSION'
validate_regex "$PRODUCTION_ENVIRONMENT" '^[A-Za-z0-9_.-]+$' 'PRODUCTION_ENVIRONMENT'

if [ "$CONFIG_SCOPE" != "sync" ]; then
  validate_regex "$PLUGIN_SLUG" '^[a-z0-9][a-z0-9-]*$' 'PLUGIN_SLUG'
  validate_regex "$ZIP_FILE" '^[A-Za-z0-9][A-Za-z0-9._-]*\.zip$' 'ZIP_FILE'
  validate_regex "$PHP_VERSION" '^[0-9]+(\.[0-9]+){0,2}$' 'PHP_VERSION'
  validate_regex "$NODE_VERSION" '^[0-9]+(\.[0-9]+){0,2}$' 'NODE_VERSION'
  validate_regex "${PHP_RUNTIME_MATRIX:-}" '^$|^[0-9]+(\.[0-9]+){0,2}(,[0-9]+(\.[0-9]+){0,2})*$' 'PHP_RUNTIME_MATRIX'
  validate_regex "$PHP_RUNTIME_MATRIX_MODE" '^(smoke|strict)$' 'PHP_RUNTIME_MATRIX_MODE'
  validate_file "$MAIN_PLUGIN_FILE" "Main plugin file"
  validate_file "$README_FILE" "Readme file"

  if [ -n "${VERSION_CONSTANT_NAME:-}" ]; then
    validate_regex "$VERSION_CONSTANT_NAME" '^[A-Z][A-Z0-9_]*$' 'VERSION_CONSTANT_NAME'
  fi

  if [ -n "${WORDPRESS_ORG_SLUG:-}" ]; then
    validate_regex "$WORDPRESS_ORG_SLUG" '^[a-z0-9][a-z0-9-]*$' 'WORDPRESS_ORG_SLUG'
  fi

  if [ -n "${POT_FILE:-}" ]; then
    validate_file "$POT_FILE" "POT file"
  fi

  if [ -n "${PACKAGE_INCLUDE:-}" ]; then
    validate_optional_paths "$PACKAGE_INCLUDE" "PACKAGE_INCLUDE"
  fi

  validate_regex "$WORDPRESS_READINESS_ENABLED" '^(true|false)$' 'WORDPRESS_READINESS_ENABLED'
  validate_regex "$WORDPRESS_QUALITY_PACK_ENABLED" '^(true|false)$' 'WORDPRESS_QUALITY_PACK_ENABLED'
  validate_regex "$WORDPRESS_SECURITY_PACK_ENABLED" '^(true|false)$' 'WORDPRESS_SECURITY_PACK_ENABLED'
  validate_regex "$WOOCOMMERCE_QIT_ENABLED" '^(true|false)$' 'WOOCOMMERCE_QIT_ENABLED'

  if wp_plugin_base_is_true "$WORDPRESS_QUALITY_PACK_ENABLED" && ! wp_plugin_base_is_true "$WORDPRESS_READINESS_ENABLED"; then
    echo "WORDPRESS_QUALITY_PACK_ENABLED=true requires WORDPRESS_READINESS_ENABLED=true." >&2
    exit 1
  fi

  if wp_plugin_base_is_true "$WORDPRESS_SECURITY_PACK_ENABLED" && ! wp_plugin_base_is_true "$WORDPRESS_READINESS_ENABLED"; then
    echo "WORDPRESS_SECURITY_PACK_ENABLED=true requires WORDPRESS_READINESS_ENABLED=true." >&2
    exit 1
  fi
fi

echo "Validated ${CONFIG_PATH} for scope ${CONFIG_SCOPE}."
