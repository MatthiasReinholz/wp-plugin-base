#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"
# shellcheck source=../lib/wordpress_tooling.sh
. "$SCRIPT_DIR/../lib/wordpress_tooling.sh"

CONFIG_OVERRIDE="${1:-}"

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

if [ -z "${POT_FILE:-}" ]; then
  echo "POT_FILE is not configured; skipping POT generation."
  exit 0
fi

wp_plugin_base_require_commands "POT generation" docker npm php
wp_plugin_base_require_vars PLUGIN_SLUG POT_FILE

POT_PATH="$(wp_plugin_base_resolve_path "$POT_FILE")"
mkdir -p "$(dirname "$POT_PATH")"

wp_env_home="$(mktemp -d)"
wp_env_config="$(mktemp)"
wp_env_tools_dir="$(mktemp -d)"
npm_cache_dir="$(mktemp -d)"
buildx_config_dir="$(mktemp -d)"
wp_env_port="$((20000 + (RANDOM % 10000)))"
wp_env_tests_port="$((30000 + (RANDOM % 10000)))"
repo_basename="$(basename "$ROOT_DIR")"
plugin_path="/var/www/html/wp-content/plugins/${repo_basename}"
pot_container_path="${plugin_path}/${POT_FILE}"
exclude_paths='.git,.github,.wp-plugin-base,.wp-plugin-base-quality-pack,dist,node_modules,tests,packages,routes'

cleanup() {
  if [ -x "$wp_env_tools_dir/node_modules/.bin/wp-env" ]; then
    WP_ENV_HOME="$wp_env_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" wp_plugin_base_wordpress_env "$wp_env_tools_dir" stop --config="$wp_env_config" >/dev/null 2>&1 || true
  fi
  rm -rf "$wp_env_home" "$wp_env_config" "$wp_env_tools_dir" "$npm_cache_dir" "$buildx_config_dir"
}

trap cleanup EXIT

WP_PLUGIN_BASE_TARGET_ROOT="$ROOT_DIR" \
WP_PLUGIN_BASE_WP_ENV_PORT="$wp_env_port" \
WP_PLUGIN_BASE_WP_ENV_TESTS_PORT="$wp_env_tests_port" \
php -r '
  $config = [
    "plugins" => [getenv("WP_PLUGIN_BASE_TARGET_ROOT")],
    "port" => (int) getenv("WP_PLUGIN_BASE_WP_ENV_PORT"),
    "testsPort" => (int) getenv("WP_PLUGIN_BASE_WP_ENV_TESTS_PORT"),
    "testsEnvironment" => false,
  ];
  file_put_contents($argv[1], json_encode($config, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);
' "$wp_env_config"

NPM_CONFIG_CACHE="$npm_cache_dir" wp_plugin_base_install_wordpress_env "$wp_env_tools_dir"

WP_ENV_HOME="$wp_env_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" wp_plugin_base_wordpress_env "$wp_env_tools_dir" start --config="$wp_env_config" >/dev/null
WP_ENV_HOME="$wp_env_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" wp_plugin_base_wordpress_env "$wp_env_tools_dir" run cli --config="$wp_env_config" -- \
  wp i18n make-pot "$plugin_path" "$pot_container_path" \
  --slug="$PLUGIN_SLUG" \
  --exclude="$exclude_paths" >/dev/null

echo "Generated POT file at $POT_FILE"
