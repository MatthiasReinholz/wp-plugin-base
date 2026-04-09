#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOUNDATION_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_SCHEMA_PATH="$FOUNDATION_DIR/docs/config-schema.json"
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

if [ ! -f "$CONFIG_SCHEMA_PATH" ]; then
  echo "Config schema not found: $CONFIG_SCHEMA_PATH" >&2
  exit 1
fi

jq -e '.schema_version == 1 and (.keys | type == "object") and (.scopes | type == "array")' "$CONFIG_SCHEMA_PATH" >/dev/null

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

validate_repo_relative_paths() {
  local raw_paths="$1"
  local label="$2"
  local require_exists="${3:-false}"
  local path
  local normalized_path
  local resolved_path

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [[ "$path" = /* ]]; then
      echo "${label} must use repo-relative paths: ${path}" >&2
      exit 1
    fi
    normalized_path="$(normalize_repo_relative_path "$path")"
    if [ -z "$normalized_path" ]; then
      echo "${label} must use repo-relative paths: ${path}" >&2
      exit 1
    fi
    if [[ "$normalized_path" =~ [[:space:]] ]]; then
      echo "${label} paths must not contain whitespace: ${path}" >&2
      exit 1
    fi
    if [[ "$normalized_path" =~ [*?\[\]\{\}] ]]; then
      echo "${label} must use explicit repo-relative paths, not glob patterns: ${path}" >&2
      exit 1
    fi
    resolved_path="$(wp_plugin_base_resolve_path "$normalized_path")"
    wp_plugin_base_assert_path_within_root "$resolved_path" "$label"
    if [ "$require_exists" = "true" ] && [ ! -e "$resolved_path" ]; then
      echo "${label} path not found: ${path}" >&2
      exit 1
    fi
  done < <(wp_plugin_base_csv_to_lines "$raw_paths")
}

normalize_repo_relative_path() {
  local path="$1"
  path="${path#./}"
  path="${path#/}"
  printf '%s\n' "$path"
}

validate_distignore_path() {
  local relative_path="$1"
  local normalized_path

  validate_repo_relative_paths "$relative_path" "DISTIGNORE_FILE"
  normalized_path="$(normalize_repo_relative_path "$relative_path")"
  if [[ ! "$normalized_path" =~ (^|/)(\.distignore|[^/]+\.distignore)$ ]]; then
    echo "DISTIGNORE_FILE must point to a repo-relative *.distignore file: ${relative_path}" >&2
    exit 1
  fi
}

validate_output_path() {
  local relative_path="$1"
  local label="$2"
  local resolved_path
  local parent_dir
  local existing_dir

  resolved_path="$(wp_plugin_base_resolve_path "$relative_path")"
  wp_plugin_base_assert_path_within_root "$resolved_path" "$label"

  parent_dir="$(dirname "$resolved_path")"
  wp_plugin_base_assert_path_within_root "$parent_dir" "${label} parent directory"

  existing_dir="$parent_dir"
  while [ ! -d "$existing_dir" ] && [ "$existing_dir" != "/" ]; do
    existing_dir="$(dirname "$existing_dir")"
  done

  if [ -e "$resolved_path" ] && [ ! -f "$resolved_path" ]; then
    echo "${label} must point to a file path, not an existing non-file entry: ${relative_path}" >&2
    exit 1
  fi

  if [ ! -d "$existing_dir" ] || [ ! -w "$existing_dir" ]; then
    echo "${label} parent directory is not writable: ${relative_path}" >&2
    exit 1
  fi
}

if ! jq -e --arg scope "$CONFIG_SCOPE" '.scopes | index($scope) != null' "$CONFIG_SCHEMA_PATH" >/dev/null; then
  echo "Unsupported config validation scope: ${CONFIG_SCOPE}" >&2
  exit 1
fi

required_keys="$(
  jq -r --arg scope "$CONFIG_SCOPE" '
    .keys
    | to_entries
    | map(select((.value.required_in_scopes // []) | index($scope) != null) | .key)
    | .[]
  ' "$CONFIG_SCHEMA_PATH"
)"

if [ -n "$required_keys" ]; then
  # shellcheck disable=SC2086
  wp_plugin_base_require_vars $required_keys
fi

validate_regex "$FOUNDATION_REPOSITORY" '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' 'FOUNDATION_REPOSITORY'
validate_regex "$FOUNDATION_VERSION" '^v[0-9]+\.[0-9]+\.[0-9]+$' 'FOUNDATION_VERSION'
validate_regex "$PRODUCTION_ENVIRONMENT" '^[A-Za-z0-9_.-]+$' 'PRODUCTION_ENVIRONMENT'

if [[ "$CONFIG_SCOPE" =~ ^(project|ci|readiness|release|deploy-structure|deploy)$ ]]; then
  validate_regex "$PLUGIN_NAME" '^[^[:cntrl:]]+$' 'PLUGIN_NAME'
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

  if [ -n "${CODEOWNERS_REVIEWERS:-}" ]; then
    validate_regex "$CODEOWNERS_REVIEWERS" '^@[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?( +@[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?)*$' 'CODEOWNERS_REVIEWERS'
  fi

  if [ -n "${WORDPRESS_ORG_SLUG:-}" ]; then
    validate_regex "$WORDPRESS_ORG_SLUG" '^[a-z0-9][a-z0-9-]*$' 'WORDPRESS_ORG_SLUG'
  fi

  if [ -n "${POT_FILE:-}" ]; then
    validate_output_path "$POT_FILE" "POT file"
  fi

  validate_distignore_path "$DISTIGNORE_FILE"

  if [ -n "${PACKAGE_INCLUDE:-}" ]; then
    validate_repo_relative_paths "$PACKAGE_INCLUDE" "PACKAGE_INCLUDE" true
  fi

  validate_repo_relative_paths "$WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE" "WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE"

  if [ -n "${PACKAGE_EXCLUDE:-}" ]; then
    validate_repo_relative_paths "$PACKAGE_EXCLUDE" "PACKAGE_EXCLUDE"
  fi

  if [ -n "${EXTRA_ALLOWED_HOSTS:-}" ]; then
    while IFS= read -r host; do
      validate_regex "$host" '^[A-Za-z0-9.-]+$' 'EXTRA_ALLOWED_HOSTS host'
    done < <(wp_plugin_base_csv_to_lines "$EXTRA_ALLOWED_HOSTS")
  fi

  validate_regex "$WORDPRESS_READINESS_ENABLED" '^(true|false)$' 'WORDPRESS_READINESS_ENABLED'
  validate_regex "$WORDPRESS_QUALITY_PACK_ENABLED" '^(true|false)$' 'WORDPRESS_QUALITY_PACK_ENABLED'
  validate_regex "$WORDPRESS_SECURITY_PACK_ENABLED" '^(true|false)$' 'WORDPRESS_SECURITY_PACK_ENABLED'
  validate_regex "$WOOCOMMERCE_QIT_ENABLED" '^(true|false)$' 'WOOCOMMERCE_QIT_ENABLED'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS:-}" '^$|^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS:-}" '^$|^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES:-}" '^$|^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES:-}" '^$|^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS:-false}" '^(true|false)$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY:-}" '^$|^[0-9]+$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY:-}" '^$|^[0-9]+$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY:-}" '^$|^[0-9]+$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY'

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
