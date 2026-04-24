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
wp_env_start_log="$(mktemp)"
wp_env_port=''
wp_env_tests_port=''
plugin_check_cli_bootstrap="/var/www/html/wp-content/plugins/plugin-check/cli.php"
max_attempts=3
attempt=1
start_success=false
plugin_check_timeout_seconds=600
timeout_bin=''

if command -v timeout >/dev/null 2>&1; then
  timeout_bin='timeout'
elif command -v gtimeout >/dev/null 2>&1; then
  timeout_bin='gtimeout'
fi

cleanup() {
  if [ -x "$wp_env_tools_dir/node_modules/.bin/wp-env" ]; then
    WP_ENV_HOME="$wp_env_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" wp_plugin_base_wordpress_env "$wp_env_tools_dir" stop --config="$wp_env_config" >/dev/null 2>&1 || true
  fi
  rm -rf "$wp_env_home" "$wp_env_config" "$wp_env_tools_dir" "$npm_cache_dir" "$buildx_config_dir" "$wp_env_start_log"
}

trap cleanup EXIT

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not available. Start Docker before running Plugin Check." >&2
  exit 1
fi

NPM_CONFIG_CACHE="$npm_cache_dir" wp_plugin_base_install_wordpress_env "$wp_env_tools_dir"
while [ "$attempt" -le "$max_attempts" ]; do
  wp_env_port="$((20000 + (RANDOM % 10000)))"
  wp_env_tests_port="$((30000 + (RANDOM % 10000)))"

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

  : > "$wp_env_start_log"

  if WP_ENV_HOME="$wp_env_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" wp_plugin_base_wordpress_env "$wp_env_tools_dir" start --config="$wp_env_config" >/dev/null 2>"$wp_env_start_log"; then
    if WP_ENV_HOME="$wp_env_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" wp_plugin_base_wordpress_env "$wp_env_tools_dir" run cli --config="$wp_env_config" -- wp plugin install plugin-check --version="$WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION" --activate >/dev/null 2>&1; then
      if WP_ENV_HOME="$wp_env_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" wp_plugin_base_wordpress_env "$wp_env_tools_dir" run cli --config="$wp_env_config" -- wp plugin is-installed plugin-check >/dev/null 2>&1; then
        start_success=true
        break
      fi
    fi
  fi

  echo "wp-env startup/install attempt ${attempt}/${max_attempts} failed (ports ${wp_env_port}/${wp_env_tests_port}); retrying." >&2
  if [ -s "$wp_env_start_log" ]; then
    echo "wp-env start stderr (attempt ${attempt}/${max_attempts}):" >&2
    cat "$wp_env_start_log" >&2
  fi
  WP_ENV_HOME="$wp_env_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" wp_plugin_base_wordpress_env "$wp_env_tools_dir" stop --config="$wp_env_config" >/dev/null 2>&1 || true
  attempt=$((attempt + 1))
done

if [ "$start_success" != true ]; then
  echo "Failed to start wp-env and install plugin-check after ${max_attempts} attempts." >&2
  exit 1
fi

installed_plugin_check_version="$(
  WP_ENV_HOME="$wp_env_home" \
    BUILDX_CONFIG="$buildx_config_dir" \
    NPM_CONFIG_CACHE="$npm_cache_dir" \
    wp_plugin_base_wordpress_env "$wp_env_tools_dir" run cli --config="$wp_env_config" -- \
    wp plugin get plugin-check --field=version
)"

if [ "$installed_plugin_check_version" != "$WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION" ]; then
  echo "Installed plugin-check version ($installed_plugin_check_version) does not match expected version ($WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION)." >&2
  exit 1
fi

plugin_check_cli_exists="$(
  WP_ENV_HOME="$wp_env_home" \
    BUILDX_CONFIG="$buildx_config_dir" \
    NPM_CONFIG_CACHE="$npm_cache_dir" \
    wp_plugin_base_wordpress_env "$wp_env_tools_dir" run cli --config="$wp_env_config" -- \
    wp eval 'echo file_exists( WP_PLUGIN_DIR . "/plugin-check/cli.php" ) ? "1" : "0";'
)"

if [ "$plugin_check_cli_exists" != "1" ]; then
  echo "Plugin Check CLI bootstrap file not found at: $plugin_check_cli_bootstrap" >&2
  exit 1
fi

repo_basename="$(basename "$ROOT_DIR")"
plugin_path="/var/www/html/wp-content/plugins/${repo_basename}/dist/package/${PLUGIN_SLUG}"
wp_env_bin="$wp_env_tools_dir/node_modules/.bin/wp-env"
plugin_check_args=(
  wp
  --require="$plugin_check_cli_bootstrap"
  plugin check "$plugin_path"
  --slug="$PLUGIN_SLUG"
  --format=strict-json
)

if [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS:-}" ]; then
  plugin_check_args+=(--checks="$WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS")
fi

if [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS:-}" ]; then
  plugin_check_args+=(--exclude-checks="$WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS")
fi

if [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES:-}" ]; then
  plugin_check_args+=(--categories="$WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES")
fi

if [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES:-}" ]; then
  plugin_check_args+=(--ignore-codes="$WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES")
fi

if [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY:-}" ]; then
  plugin_check_args+=(--severity="$WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY")
fi

if [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY:-}" ]; then
  plugin_check_args+=(--error-severity="$WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY")
fi

if [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY:-}" ]; then
  plugin_check_args+=(--warning-severity="$WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY")
fi

plugin_check_command=(
  "$wp_env_bin" run cli --config="$wp_env_config" --
  "${plugin_check_args[@]}"
)

run_plugin_check_with_php_timeout() {
  local status

  set +e
  raw_output="$(
    WP_ENV_HOME="$wp_env_home" \
      BUILDX_CONFIG="$buildx_config_dir" \
      NPM_CONFIG_CACHE="$npm_cache_dir" \
      php "$SCRIPT_DIR/run_with_php_timeout.php" "$plugin_check_timeout_seconds" "${plugin_check_command[@]}"
  )"
  status="$?"
  set -e
  if [ "$status" -ne 0 ]; then
    if [ "$status" -eq 124 ]; then
      echo "Plugin Check timed out after ${plugin_check_timeout_seconds}s." >&2
    fi
    exit "$status"
  fi
}

if [ -n "$timeout_bin" ]; then
  set +e
  raw_output="$(
    WP_ENV_HOME="$wp_env_home" \
      BUILDX_CONFIG="$buildx_config_dir" \
      NPM_CONFIG_CACHE="$npm_cache_dir" \
      "$timeout_bin" "$plugin_check_timeout_seconds" "${plugin_check_command[@]}"
  )"
  status="$?"
  set -e
  if [ "$status" -ne 0 ]; then
    if [ "$status" -eq 124 ]; then
      echo "Plugin Check timed out after ${plugin_check_timeout_seconds}s." >&2
    fi
    exit "$status"
  fi
else
  run_plugin_check_with_php_timeout
fi

json_payload="$(printf '%s\n' "$raw_output" | bash "$SCRIPT_DIR/normalize_plugin_check_output.sh")"

printf '%s\n' "$json_payload" > "$REPORT_PATH"

error_count="$(printf '%s\n' "$json_payload" | jq '[ .[] | select(.type == "ERROR") ] | length')"
warning_count="$(printf '%s\n' "$json_payload" | jq '[ .[] | select(.type == "WARNING") ] | length')"

printf 'Plugin Check: %s errors, %s warnings.\n' "$error_count" "$warning_count"

if [ "$error_count" -gt 0 ]; then
  echo "Plugin Check reported errors. See dist/plugin-check.json." >&2
  exit 1
fi

if wp_plugin_base_is_true "${WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS:-false}" && [ "$warning_count" -gt 0 ]; then
  echo "Plugin Check reported warnings and strict warnings mode is enabled. See dist/plugin-check.json." >&2
  exit 1
fi
