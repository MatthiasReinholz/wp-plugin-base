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
