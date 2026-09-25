#!/usr/bin/env bash

set -euo pipefail

WP_PLUGIN_BASE_COMPOSER_IMAGE='composer@sha256:9715c7f69044da2a212a5fbde29ee7da24e364d426560ae6367b060236f847d7'
WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION='2.1.0'

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

# Only call for an environment whose home/config/tool directories this task created.
# Preserve every recovery input when Docker cleanup fails; never discard its identity.
wp_plugin_base_cleanup_temporary_wordpress_env() {
  local install_dir="$1"
  local environment_home="$2"
  local environment_config="$3"
  local npm_cache_dir="$4"
  local buildx_config_dir="$5"
  local start_attempted="$6"
  shift 6

  if [ "$start_attempted" = true ]; then
    if ! WP_ENV_HOME="$environment_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" \
      wp_plugin_base_wordpress_env "$install_dir" cleanup --force --config="$environment_config" >/dev/null 2>&1; then
      echo "Temporary WordPress environment cleanup failed; retaining configuration and tools for recovery." >&2
      printf 'Retry: WP_ENV_HOME=%q BUILDX_CONFIG=%q NPM_CONFIG_CACHE=%q %q cleanup --force --config=%q\n' \
        "$environment_home" "$buildx_config_dir" "$npm_cache_dir" "$install_dir/node_modules/.bin/wp-env" "$environment_config" >&2
      return 1
    fi
  fi

  rm -rf "$environment_home" "$environment_config" "$install_dir" "$npm_cache_dir" "$buildx_config_dir" "$@"
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
