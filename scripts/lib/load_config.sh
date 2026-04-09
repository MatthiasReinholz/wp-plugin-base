#!/usr/bin/env bash

set -euo pipefail

wp_plugin_base_is_supported_config_key() {
  case "$1" in
    FOUNDATION_REPOSITORY|FOUNDATION_VERSION|PLUGIN_NAME|PLUGIN_SLUG|MAIN_PLUGIN_FILE|README_FILE|ZIP_FILE|PHP_VERSION|NODE_VERSION|PRODUCTION_ENVIRONMENT|PHP_RUNTIME_MATRIX|PHP_RUNTIME_MATRIX_MODE|VERSION_CONSTANT_NAME|POT_FILE|POT_PROJECT_NAME|WORDPRESS_ORG_SLUG|WORDPRESS_READINESS_ENABLED|WORDPRESS_QUALITY_PACK_ENABLED|WORDPRESS_SECURITY_PACK_ENABLED|WOOCOMMERCE_QIT_ENABLED|WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS|WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS|WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES|WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES|WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS|WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY|WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY|WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY|EXTRA_ALLOWED_HOSTS|WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE|PACKAGE_INCLUDE|PACKAGE_EXCLUDE|CHANGELOG_HEADING|CODEOWNERS_REVIEWERS|DISTIGNORE_FILE|SVN_USERNAME|SVN_PASSWORD)
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
  PHP_RUNTIME_MATRIX="${PHP_RUNTIME_MATRIX:-}"
  PHP_RUNTIME_MATRIX_MODE="${PHP_RUNTIME_MATRIX_MODE:-smoke}"
  WORDPRESS_READINESS_ENABLED="${WORDPRESS_READINESS_ENABLED:-false}"
  WORDPRESS_QUALITY_PACK_ENABLED="${WORDPRESS_QUALITY_PACK_ENABLED:-false}"
  WORDPRESS_SECURITY_PACK_ENABLED="${WORDPRESS_SECURITY_PACK_ENABLED:-false}"
  WOOCOMMERCE_QIT_ENABLED="${WOOCOMMERCE_QIT_ENABLED:-false}"
  WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE="${WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE:-.wp-plugin-base-security-suppressions.json}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS="${WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS:-}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS="${WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS:-}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES="${WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES:-}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES="${WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES:-}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS="${WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS:-false}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY="${WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY:-}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY="${WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY:-}"
  WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY="${WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY:-}"
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
