#!/usr/bin/env bash

set -euo pipefail

LOAD_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=provider.sh
. "$LOAD_CONFIG_DIR/provider.sh"

wp_plugin_base_is_supported_config_key() {
  case "$1" in
    FOUNDATION_REPOSITORY|FOUNDATION_VERSION|FOUNDATION_RELEASE_SOURCE_PROVIDER|FOUNDATION_RELEASE_SOURCE_REFERENCE|FOUNDATION_RELEASE_SOURCE_API_BASE|FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER|AUTOMATION_PROVIDER|AUTOMATION_API_BASE|TRUSTED_GIT_HOSTS|PLUGIN_RUNTIME_UPDATE_PROVIDER|PLUGIN_RUNTIME_UPDATE_SOURCE_URL|PLUGIN_NAME|PLUGIN_SLUG|MAIN_PLUGIN_FILE|README_FILE|ZIP_FILE|PHP_VERSION|NODE_VERSION|PRODUCTION_ENVIRONMENT|PHP_RUNTIME_MATRIX|PHP_RUNTIME_MATRIX_MODE|PHPSTAN_MEMORY_LIMIT|VERSION_CONSTANT_NAME|POT_FILE|POT_PROJECT_NAME|WORDPRESS_ORG_SLUG|WORDPRESS_READINESS_ENABLED|WORDPRESS_QUALITY_PACK_ENABLED|WORDPRESS_SECURITY_PACK_ENABLED|RELEASE_READINESS_MODE|WOOCOMMERCE_QIT_ENABLED|WOOCOMMERCE_COM_PRODUCT_ID|WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS|GITHUB_RELEASE_UPDATER_ENABLED|GITHUB_RELEASE_UPDATER_REPO_URL|REST_OPERATIONS_PACK_ENABLED|REST_API_NAMESPACE|REST_ABILITIES_ENABLED|ADMIN_UI_PACK_ENABLED|ADMIN_UI_STARTER|ADMIN_UI_EXPERIMENTAL_DATAVIEWS|ADMIN_UI_NPM_AUDIT_LEVEL|WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS|WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS|WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES|WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES|WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS|WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY|WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY|WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY|EXTRA_ALLOWED_HOSTS|WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE|PACKAGE_INCLUDE|PACKAGE_EXCLUDE|CHANGELOG_HEADING|CODEOWNERS_REVIEWERS|DISTIGNORE_FILE|BUILD_SCRIPT|BUILD_SCRIPT_ARGS|PHPDOC_VERSION_REPLACEMENT_ENABLED|PHPDOC_VERSION_PLACEHOLDER|CHANGELOG_MD_SYNC_ENABLED|CHANGELOG_SOURCE|SIMULATE_RELEASE_WORKFLOW_ENABLED|GLOTPRESS_TRIGGER_ENABLED|GLOTPRESS_URL|GLOTPRESS_PROJECT_SLUG|GLOTPRESS_FAIL_ON_ERROR|DEPLOY_NOTIFICATION_ENABLED)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

wp_plugin_base_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

wp_plugin_base_root() {
  if [ -n "${WP_PLUGIN_BASE_ROOT:-}" ]; then
    printf '%s\n' "$WP_PLUGIN_BASE_ROOT"
    return
  fi

  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return
  fi

  pwd
}

wp_plugin_base_config_path() {
  local root_dir="$1"
  local config_path="${2:-${WP_PLUGIN_BASE_CONFIG:-.wp-plugin-base.env}}"

  if [[ "$config_path" = /* ]]; then
    printf '%s\n' "$config_path"
    return
  fi

  printf '%s/%s\n' "$root_dir" "$config_path"
}

wp_plugin_base_config_error() {
  local config_path="$1"
  local line_number="$2"
  local message="$3"

  echo "${config_path}:${line_number}: ${message}" >&2
  exit 1
}

wp_plugin_base_parse_config_value() {
  local raw_value="$1"
  local config_path="$2"
  local line_number="$3"
  local value

  value="$(wp_plugin_base_trim "$raw_value")"

  case "$value" in
    \"*\")
      if [ "${#value}" -lt 2 ] || [ "${value: -1}" != '"' ]; then
        wp_plugin_base_config_error "$config_path" "$line_number" "unterminated double-quoted value"
      fi
      value="${value:1:${#value}-2}"
      value="${value//\\\\/\\}"
      value="${value//\\\"/\"}"
      ;;
    \'*\')
      if [ "${#value}" -lt 2 ] || [ "${value: -1}" != "'" ]; then
        wp_plugin_base_config_error "$config_path" "$line_number" "unterminated single-quoted value"
      fi
      value="${value:1:${#value}-2}"
      ;;
    *)
      if [[ "$value" =~ [[:space:]] ]]; then
        wp_plugin_base_config_error "$config_path" "$line_number" "unquoted values must not contain whitespace"
      fi
      ;;
  esac

  printf '%s' "$value"
}

wp_plugin_base_default_api_base() {
  local provider="$1"
  wp_plugin_base_provider_default_api_base "$provider"
}

wp_plugin_base_warn_config() {
  printf 'Warning: %s\n' "$1" >&2
}

wp_plugin_base_load_config() {
  ROOT_DIR="$(wp_plugin_base_root)"
  CONFIG_PATH="$(wp_plugin_base_config_path "$ROOT_DIR" "${1:-}")"

  if [ ! -f "$CONFIG_PATH" ]; then
    echo "Config file not found: $CONFIG_PATH" >&2
    exit 1
  fi

  ROOT_DIR="$(cd "$ROOT_DIR" && pwd -P)"
  CONFIG_PATH="$(cd "$(dirname "$CONFIG_PATH")" && pwd -P)/$(basename "$CONFIG_PATH")"

  local line=""
  local line_number=0
  local trimmed_line=""
  local key=""
  local raw_value=""
  local parsed_value=""

  while IFS= read -r line || [ -n "$line" ]; do
    line_number=$((line_number + 1))
    trimmed_line="$(wp_plugin_base_trim "$line")"

    if [ -z "$trimmed_line" ] || [[ "$trimmed_line" == \#* ]]; then
      continue
    fi

    if [[ ! "$trimmed_line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      wp_plugin_base_config_error "$CONFIG_PATH" "$line_number" "expected KEY=value syntax"
    fi

    key="${BASH_REMATCH[1]}"
    if ! wp_plugin_base_is_supported_config_key "$key"; then
      wp_plugin_base_config_error "$CONFIG_PATH" "$line_number" "unknown config key: $key"
    fi
    raw_value="${BASH_REMATCH[2]}"
    parsed_value="$(wp_plugin_base_parse_config_value "$raw_value" "$CONFIG_PATH" "$line_number")"
    export "$key=$parsed_value"
  done < "$CONFIG_PATH"

  README_FILE="${README_FILE:-readme.txt}"
  CHANGELOG_HEADING="${CHANGELOG_HEADING:-Changelog}"
  DISTIGNORE_FILE="${DISTIGNORE_FILE:-.distignore}"
  PRODUCTION_ENVIRONMENT="${PRODUCTION_ENVIRONMENT:-production}"
  AUTOMATION_PROVIDER="${AUTOMATION_PROVIDER:-github}"
  AUTOMATION_API_BASE="${AUTOMATION_API_BASE:-$(wp_plugin_base_default_api_base "$AUTOMATION_PROVIDER")}"
  TRUSTED_GIT_HOSTS="${TRUSTED_GIT_HOSTS:-}"
  PHP_RUNTIME_MATRIX="${PHP_RUNTIME_MATRIX:-}"
  PHP_RUNTIME_MATRIX_MODE="${PHP_RUNTIME_MATRIX_MODE:-smoke}"
  PHPSTAN_MEMORY_LIMIT="${PHPSTAN_MEMORY_LIMIT:-}"
  FOUNDATION_RELEASE_SOURCE_PROVIDER="${FOUNDATION_RELEASE_SOURCE_PROVIDER:-}"
  FOUNDATION_RELEASE_SOURCE_REFERENCE="${FOUNDATION_RELEASE_SOURCE_REFERENCE:-}"
  FOUNDATION_RELEASE_SOURCE_API_BASE="${FOUNDATION_RELEASE_SOURCE_API_BASE:-}"
  FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER="${FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER:-}"

  if [ -z "$FOUNDATION_RELEASE_SOURCE_PROVIDER" ]; then
    if [ -n "${FOUNDATION_REPOSITORY:-}" ]; then
      FOUNDATION_RELEASE_SOURCE_PROVIDER="github-release"
    else
      FOUNDATION_RELEASE_SOURCE_PROVIDER="github-release"
    fi
  fi
  if [ -z "$FOUNDATION_RELEASE_SOURCE_REFERENCE" ]; then
    FOUNDATION_RELEASE_SOURCE_REFERENCE="${FOUNDATION_REPOSITORY:-}"
  fi
  if [ -z "$FOUNDATION_RELEASE_SOURCE_API_BASE" ]; then
    FOUNDATION_RELEASE_SOURCE_API_BASE="$(wp_plugin_base_default_api_base "$FOUNDATION_RELEASE_SOURCE_PROVIDER")"
  fi

  if [ -z "${FOUNDATION_REPOSITORY:-}" ] && [ "$FOUNDATION_RELEASE_SOURCE_PROVIDER" = "github-release" ]; then
    FOUNDATION_REPOSITORY="$FOUNDATION_RELEASE_SOURCE_REFERENCE"
  fi

  WORDPRESS_READINESS_ENABLED="${WORDPRESS_READINESS_ENABLED:-false}"
  WORDPRESS_QUALITY_PACK_ENABLED="${WORDPRESS_QUALITY_PACK_ENABLED:-false}"
  WORDPRESS_SECURITY_PACK_ENABLED="${WORDPRESS_SECURITY_PACK_ENABLED:-false}"
  RELEASE_READINESS_MODE="${RELEASE_READINESS_MODE:-standard}"
  WOOCOMMERCE_QIT_ENABLED="${WOOCOMMERCE_QIT_ENABLED:-false}"
  WOOCOMMERCE_COM_PRODUCT_ID="${WOOCOMMERCE_COM_PRODUCT_ID:-}"
  WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS="${WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS:-30}"

  plugin_runtime_update_provider_was_set=false
  plugin_runtime_update_source_url_was_set=false
  github_release_updater_enabled_was_set=false
  github_release_updater_repo_url_was_set=false
  changelog_source_was_set=false

  if [ "${PLUGIN_RUNTIME_UPDATE_PROVIDER+x}" = x ]; then
    plugin_runtime_update_provider_was_set=true
  fi
  if [ "${PLUGIN_RUNTIME_UPDATE_SOURCE_URL+x}" = x ]; then
    plugin_runtime_update_source_url_was_set=true
  fi
  if [ "${GITHUB_RELEASE_UPDATER_ENABLED+x}" = x ]; then
    github_release_updater_enabled_was_set=true
  fi
  if [ "${GITHUB_RELEASE_UPDATER_REPO_URL+x}" = x ]; then
    github_release_updater_repo_url_was_set=true
  fi
  if [ "${CHANGELOG_SOURCE+x}" = x ]; then
    changelog_source_was_set=true
  fi

  PLUGIN_RUNTIME_UPDATE_PROVIDER="${PLUGIN_RUNTIME_UPDATE_PROVIDER:-}"
  PLUGIN_RUNTIME_UPDATE_SOURCE_URL="${PLUGIN_RUNTIME_UPDATE_SOURCE_URL:-}"
  GITHUB_RELEASE_UPDATER_ENABLED="${GITHUB_RELEASE_UPDATER_ENABLED:-false}"
  GITHUB_RELEASE_UPDATER_REPO_URL="${GITHUB_RELEASE_UPDATER_REPO_URL:-}"

  if [ -z "$PLUGIN_RUNTIME_UPDATE_PROVIDER" ]; then
    if wp_plugin_base_is_true "$GITHUB_RELEASE_UPDATER_ENABLED"; then
      PLUGIN_RUNTIME_UPDATE_PROVIDER="github-release"
    else
      PLUGIN_RUNTIME_UPDATE_PROVIDER="none"
    fi
  fi
  if [ -z "$PLUGIN_RUNTIME_UPDATE_SOURCE_URL" ]; then
    PLUGIN_RUNTIME_UPDATE_SOURCE_URL="$GITHUB_RELEASE_UPDATER_REPO_URL"
  fi

  if [ "$plugin_runtime_update_provider_was_set" = true ] && [ "$github_release_updater_enabled_was_set" = true ]; then
    expected_legacy_enabled="false"
    if [ "$PLUGIN_RUNTIME_UPDATE_PROVIDER" = "github-release" ]; then
      expected_legacy_enabled="true"
    fi
    if [ "$GITHUB_RELEASE_UPDATER_ENABLED" != "$expected_legacy_enabled" ]; then
      wp_plugin_base_warn_config "PLUGIN_RUNTIME_UPDATE_PROVIDER=${PLUGIN_RUNTIME_UPDATE_PROVIDER} overrides conflicting legacy GITHUB_RELEASE_UPDATER_ENABLED=${GITHUB_RELEASE_UPDATER_ENABLED}."
    fi
  fi

  if [ "$plugin_runtime_update_source_url_was_set" = true ] && [ "$github_release_updater_repo_url_was_set" = true ] && [ "$PLUGIN_RUNTIME_UPDATE_PROVIDER" = "github-release" ] && [ "$PLUGIN_RUNTIME_UPDATE_SOURCE_URL" != "$GITHUB_RELEASE_UPDATER_REPO_URL" ]; then
    wp_plugin_base_warn_config "PLUGIN_RUNTIME_UPDATE_SOURCE_URL overrides conflicting legacy GITHUB_RELEASE_UPDATER_REPO_URL=${GITHUB_RELEASE_UPDATER_REPO_URL}."
  fi

  if [ "${GITHUB_RELEASE_UPDATER_ENABLED:-false}" != "true" ] && [ "$PLUGIN_RUNTIME_UPDATE_PROVIDER" = "github-release" ]; then
    GITHUB_RELEASE_UPDATER_ENABLED="true"
  fi
  if [ "$PLUGIN_RUNTIME_UPDATE_PROVIDER" != "github-release" ]; then
    GITHUB_RELEASE_UPDATER_ENABLED="false"
  fi
  if [ -z "$GITHUB_RELEASE_UPDATER_REPO_URL" ] && [ "$PLUGIN_RUNTIME_UPDATE_PROVIDER" = "github-release" ]; then
    GITHUB_RELEASE_UPDATER_REPO_URL="$PLUGIN_RUNTIME_UPDATE_SOURCE_URL"
  fi

  REST_OPERATIONS_PACK_ENABLED="${REST_OPERATIONS_PACK_ENABLED:-false}"
  REST_API_NAMESPACE="${REST_API_NAMESPACE:-${PLUGIN_SLUG:-plugin}/v1}"
  REST_ABILITIES_ENABLED="${REST_ABILITIES_ENABLED:-false}"
  ADMIN_UI_PACK_ENABLED="${ADMIN_UI_PACK_ENABLED:-false}"
  if [ "${ADMIN_UI_STARTER+x}" = x ]; then
    ADMIN_UI_STARTER_WAS_SET="true"
  else
    ADMIN_UI_STARTER_WAS_SET="false"
  fi
  if [ "${ADMIN_UI_EXPERIMENTAL_DATAVIEWS+x}" = x ]; then
    ADMIN_UI_EXPERIMENTAL_DATAVIEWS_WAS_SET="true"
  else
    ADMIN_UI_EXPERIMENTAL_DATAVIEWS_WAS_SET="false"
  fi
  ADMIN_UI_STARTER="${ADMIN_UI_STARTER:-}"
  ADMIN_UI_EXPERIMENTAL_DATAVIEWS_RAW="${ADMIN_UI_EXPERIMENTAL_DATAVIEWS:-false}"
  ADMIN_UI_EXPERIMENTAL_DATAVIEWS="${ADMIN_UI_EXPERIMENTAL_DATAVIEWS_RAW}"
  if [ -z "$ADMIN_UI_STARTER" ]; then
    if wp_plugin_base_is_true "$ADMIN_UI_EXPERIMENTAL_DATAVIEWS"; then
      ADMIN_UI_STARTER="dataviews"
    else
      ADMIN_UI_STARTER="basic"
    fi
  fi

  if [ "$ADMIN_UI_STARTER" = "dataviews" ]; then
    ADMIN_UI_EXPERIMENTAL_DATAVIEWS="true"
  else
    ADMIN_UI_EXPERIMENTAL_DATAVIEWS="false"
  fi
  ADMIN_UI_NPM_AUDIT_LEVEL="${ADMIN_UI_NPM_AUDIT_LEVEL:-high}"
  WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE="${WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE:-.wp-plugin-base-security-suppressions.json}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS="${WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS:-}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS="${WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS:-}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES="${WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES:-}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES="${WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES:-}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS="${WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS:-false}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY="${WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY:-}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY="${WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY:-}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY="${WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY:-}"
  BUILD_SCRIPT="${BUILD_SCRIPT:-}"
  BUILD_SCRIPT_ARGS="${BUILD_SCRIPT_ARGS:-}"
  PHPDOC_VERSION_REPLACEMENT_ENABLED="${PHPDOC_VERSION_REPLACEMENT_ENABLED:-false}"
  PHPDOC_VERSION_PLACEHOLDER="${PHPDOC_VERSION_PLACEHOLDER:-NEXT}"
  CHANGELOG_MD_SYNC_ENABLED="${CHANGELOG_MD_SYNC_ENABLED:-false}"
  CHANGELOG_SOURCE="${CHANGELOG_SOURCE:-commits}"
  if [ "$CHANGELOG_SOURCE" = "prs_titles" ]; then
    if [ "$changelog_source_was_set" = true ]; then
      wp_plugin_base_warn_config "CHANGELOG_SOURCE=prs_titles is deprecated; use CHANGELOG_SOURCE=change_request_titles."
    fi
    CHANGELOG_SOURCE="change_request_titles"
  fi
  SIMULATE_RELEASE_WORKFLOW_ENABLED="${SIMULATE_RELEASE_WORKFLOW_ENABLED:-false}"
  GLOTPRESS_TRIGGER_ENABLED="${GLOTPRESS_TRIGGER_ENABLED:-false}"
  GLOTPRESS_URL="${GLOTPRESS_URL:-}"
  GLOTPRESS_PROJECT_SLUG="${GLOTPRESS_PROJECT_SLUG:-}"
  GLOTPRESS_FAIL_ON_ERROR="${GLOTPRESS_FAIL_ON_ERROR:-false}"
  DEPLOY_NOTIFICATION_ENABLED="${DEPLOY_NOTIFICATION_ENABLED:-false}"
}

wp_plugin_base_require_vars() {
  local key

  for key in "$@"; do
    if [ -z "${!key:-}" ]; then
      echo "Required config value is missing: $key" >&2
      exit 1
    fi
  done
}

wp_plugin_base_resolve_path() {
  local value="$1"

  if [[ "$value" = /* ]]; then
    printf '%s\n' "$value"
    return
  fi

  printf '%s/%s\n' "$ROOT_DIR" "$value"
}

wp_plugin_base_canonicalize_path() {
  local path="$1"
  local directory
  local existing_dir
  local suffix=""
  local canonical_directory
  local basename

  directory="$(dirname "$path")"
  existing_dir="$directory"
  while [ ! -d "$existing_dir" ] && [ "$existing_dir" != "/" ]; do
    suffix="/$(basename "$existing_dir")${suffix}"
    existing_dir="$(dirname "$existing_dir")"
  done

  if [ ! -d "$existing_dir" ]; then
    echo "Unable to resolve path: $path" >&2
    exit 1
  fi

  canonical_directory="$(cd "$existing_dir" && pwd -P)${suffix}"
  basename="$(basename "$path")"

  if [ "$basename" = "." ]; then
    printf '%s\n' "$canonical_directory"
    return
  fi

  printf '%s/%s\n' "$canonical_directory" "$basename"
}

wp_plugin_base_assert_path_within_root() {
  local path="$1"
  local label="$2"
  local canonical_path

  canonical_path="$(wp_plugin_base_canonicalize_path "$path")"

  case "$canonical_path" in
    "$ROOT_DIR"|"$ROOT_DIR"/*)
      ;;
    *)
      echo "${label} must stay within the repository root: ${path}" >&2
      exit 1
      ;;
  esac
}

wp_plugin_base_read_header_value() {
  local file="$1"
  local label="$2"
  local value

  value="$(sed -n "s/^ \\* ${label}: //p" "$file" | head -n 1)"

  if [ -z "$value" ]; then
    value="$(sed -n "s/^${label}: //p" "$file" | head -n 1)"
  fi

  wp_plugin_base_trim "$value"
}

wp_plugin_base_read_define_value() {
  local file="$1"
  local constant_name="$2"

  perl -ne '
    if (/define\(\s*["'\'']'"$constant_name"'["'\'']\s*,\s*["'\'']([^"'\'']+)["'\'']\s*\)/) {
      print "$1\n";
      exit 0;
    }
  ' "$file" | head -n 1
}

wp_plugin_base_csv_to_lines() {
  local raw="${1:-}"

  if [ -z "$raw" ]; then
    return 0
  fi

  printf '%s\n' "$raw" | tr ',' '\n' | while IFS= read -r item; do
    item="$(wp_plugin_base_trim "$item")"
    if [ -n "$item" ]; then
      printf '%s\n' "$item"
    fi
  done
}

wp_plugin_base_is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}
