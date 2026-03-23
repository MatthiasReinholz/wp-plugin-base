#!/usr/bin/env bash

set -euo pipefail

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

wp_plugin_base_load_config() {
  ROOT_DIR="$(wp_plugin_base_root)"
  CONFIG_PATH="$(wp_plugin_base_config_path "$ROOT_DIR" "${1:-}")"

  if [ ! -f "$CONFIG_PATH" ]; then
    echo "Config file not found: $CONFIG_PATH" >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  . "$CONFIG_PATH"
  set +a

  README_FILE="${README_FILE:-readme.txt}"
  CHANGELOG_HEADING="${CHANGELOG_HEADING:-Changelog}"
  DISTIGNORE_FILE="${DISTIGNORE_FILE:-.distignore}"
  PRODUCTION_ENVIRONMENT="${PRODUCTION_ENVIRONMENT:-production}"
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
