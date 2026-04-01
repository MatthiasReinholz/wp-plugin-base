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

wp_plugin_base_require_commands "Plugin Check" docker jq npm php zip unzip
wp_plugin_base_load_config "$CONFIG_OVERRIDE"
wp_plugin_base_require_vars PLUGIN_SLUG

PACKAGE_ROOT="$ROOT_DIR/dist/package/$PLUGIN_SLUG"
REPORT_PATH="$ROOT_DIR/dist/plugin-check.json"

if [ ! -d "$PACKAGE_ROOT" ]; then
  echo "Plugin Check requires a packaged plugin directory at: $PACKAGE_ROOT" >&2
  exit 1
fi

wp_env_home="$(mktemp -d)"
wp_env_config="$(mktemp)"
wp_env_tools_dir="$(mktemp -d)"
npm_cache_dir="$(mktemp -d)"
buildx_config_dir="$(mktemp -d)"
wp_env_port="$((20000 + (RANDOM % 10000)))"
wp_env_tests_port="$((30000 + (RANDOM % 10000)))"

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
WP_ENV_HOME="$wp_env_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" wp_plugin_base_wordpress_env "$wp_env_tools_dir" run cli --config="$wp_env_config" -- wp plugin install plugin-check --version="$WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION" --activate >/dev/null

repo_basename="$(basename "$ROOT_DIR")"
plugin_path="/var/www/html/wp-content/plugins/${repo_basename}/dist/package/${PLUGIN_SLUG}"
raw_output="$(
  WP_ENV_HOME="$wp_env_home" \
    BUILDX_CONFIG="$buildx_config_dir" \
    NPM_CONFIG_CACHE="$npm_cache_dir" \
    wp_plugin_base_wordpress_env "$wp_env_tools_dir" run cli --config="$wp_env_config" -- \
    wp plugin check "$plugin_path" --slug="$PLUGIN_SLUG" --format=strict-json
)"

json_payload="$raw_output"

if [ -z "$json_payload" ]; then
  json_payload='[]'
fi

if [ "$json_payload" = 'Success: Checks complete. No errors found.' ]; then
  json_payload='[]'
fi

if ! printf '%s\n' "$json_payload" | jq -e 'type == "array"' >/dev/null 2>&1; then
  json_payload="$(
    printf '%s\n' "$raw_output" | perl -0ne '
      if (/(\[[\s\S]*\])(?:✔ Ran|\z)/) {
        print $1;
        exit 0;
      }
      exit 1;
    '
  )"
fi

printf '%s\n' "$json_payload" > "$REPORT_PATH"

error_count="$(printf '%s\n' "$json_payload" | jq '[ .[] | select(.type == "ERROR") ] | length')"
warning_count="$(printf '%s\n' "$json_payload" | jq '[ .[] | select(.type == "WARNING") ] | length')"

printf 'Plugin Check: %s errors, %s warnings.\n' "$error_count" "$warning_count"

if [ "$error_count" -gt 0 ]; then
  echo "Plugin Check reported errors. See dist/plugin-check.json." >&2
  exit 1
fi
