#!/usr/bin/env bash

set -euo pipefail

WP_PLUGIN_BASE_COMPOSER_IMAGE='composer@sha256:743aebe48ca67097c36819040633ea77e44a561eca135e4fc84c002e63a1ba07'
WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION='1.9.0'

wp_plugin_base_wordpress_tools_dir() {
  local script_dir

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s\n' "$(cd "$script_dir/../../tools/wordpress-env" && pwd)"
}

wp_plugin_base_install_wordpress_env() {
  local destination_dir="$1"
  local source_dir

  source_dir="$(wp_plugin_base_wordpress_tools_dir)"

  cp "$source_dir/.npmrc" "$source_dir/package.json" "$source_dir/package-lock.json" "$destination_dir/"

  (
    cd "$destination_dir"
    npm ci --no-audit --no-fund >/dev/null
  )
}

wp_plugin_base_wordpress_env() {
  local install_dir="$1"
  shift
  "$install_dir/node_modules/.bin/wp-env" "$@"
}

wp_plugin_base_wordpress_env_start_with_retry() {
  local install_dir="$1"
  shift

  local max_attempts="${WP_PLUGIN_BASE_WP_ENV_START_ATTEMPTS:-3}"
  local attempt=1
  local retry_delay="${WP_PLUGIN_BASE_WP_ENV_RETRY_DELAY_SECONDS:-5}"
  local start_log

  start_log="$(mktemp)"

  while [ "$attempt" -le "$max_attempts" ]; do
    : > "$start_log"

    if wp_plugin_base_wordpress_env "$install_dir" start "$@" >/dev/null 2>"$start_log"; then
      rm -f "$start_log"
      return 0
    fi

    echo "wp-env start attempt ${attempt}/${max_attempts} failed; retrying." >&2
    if [ -s "$start_log" ]; then
      echo "wp-env start stderr (attempt ${attempt}/${max_attempts}):" >&2
      cat "$start_log" >&2
    fi

    wp_plugin_base_wordpress_env "$install_dir" stop "$@" >/dev/null 2>&1 || true

    attempt=$((attempt + 1))
    if [ "$attempt" -le "$max_attempts" ]; then
      sleep "$retry_delay"
    fi
  done

  rm -f "$start_log"
  echo "Failed to start wp-env after ${max_attempts} attempts." >&2
  return 1
}
