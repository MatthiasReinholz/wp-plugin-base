#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$ROOT_DIR/scripts/lib/require_tools.sh"
# shellcheck source=../lib/wordpress_tooling.sh
. "$ROOT_DIR/scripts/lib/wordpress_tooling.sh"

wp_plugin_base_require_commands "runtime pack WordPress smoke tests" docker npm php rsync zip unzip

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not available. Start Docker before running runtime pack WordPress smoke tests." >&2
  exit 1
fi

wp_env_home="$(mktemp -d)"
wp_env_tools_dir="$(mktemp -d)"
npm_cache_dir="$(mktemp -d)"
buildx_config_dir="$(mktemp -d)"

cleanup() {
  if [ -x "$wp_env_tools_dir/node_modules/.bin/wp-env" ]; then
    WP_ENV_HOME="$wp_env_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" wp_plugin_base_wordpress_env "$wp_env_tools_dir" stop >/dev/null 2>&1 || true
  fi

  rm -rf "$wp_env_home" "$wp_env_tools_dir" "$npm_cache_dir" "$buildx_config_dir" 2>/dev/null || true
}

trap cleanup EXIT

NPM_CONFIG_CACHE="$npm_cache_dir" wp_plugin_base_install_wordpress_env "$wp_env_tools_dir"

run_variant() {
  local variant_name="$1"
  local enable_dataviews="$2"
  local fixture_dir=""
  local wp_env_config=""
  local wp_eval_file=""
  local container_eval_file=""
  local wp_env_port=""
  local wp_env_tests_port=""
  local mounted_plugin_dir=""
  local plugin_entry=""

  fixture_dir="$(mktemp -d)"
  wp_env_config="$(mktemp)"
  wp_eval_file="$(mktemp)"

  cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$fixture_dir/"
  mkdir -p "$fixture_dir/.wp-plugin-base"

  if [ "$enable_dataviews" = "true" ]; then
    printf '\nADMIN_UI_STARTER=dataviews\n' >> "$fixture_dir/.wp-plugin-base.env"
  fi

  rsync -a --exclude '.git' "$ROOT_DIR/" "$fixture_dir/.wp-plugin-base/"

  WP_PLUGIN_BASE_ROOT="$fixture_dir" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
  WP_PLUGIN_BASE_ROOT="$fixture_dir" bash "$ROOT_DIR/scripts/ci/validate_project.sh"

  wp_env_port="$((20000 + (RANDOM % 10000)))"
  wp_env_tests_port="$((30000 + (RANDOM % 10000)))"

  WP_PLUGIN_BASE_TARGET_ROOT="$fixture_dir" \
  WP_PLUGIN_BASE_WP_ENV_PORT="$wp_env_port" \
  WP_PLUGIN_BASE_WP_ENV_TESTS_PORT="$wp_env_tests_port" \
  php -r '
    $config = array(
      "plugins"          => array( getenv( "WP_PLUGIN_BASE_TARGET_ROOT" ) ),
      "port"             => (int) getenv( "WP_PLUGIN_BASE_WP_ENV_PORT" ),
      "testsPort"        => (int) getenv( "WP_PLUGIN_BASE_WP_ENV_TESTS_PORT" ),
      "testsEnvironment" => false,
    );
    file_put_contents( $argv[1], json_encode( $config, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES ) . PHP_EOL );
  ' "$wp_env_config"

  WP_ENV_HOME="$wp_env_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" \
    wp_plugin_base_wordpress_env "$wp_env_tools_dir" start --config="$wp_env_config" >/dev/null

  mounted_plugin_dir="$(basename "$fixture_dir")"
  plugin_entry="${mounted_plugin_dir}/runtime-pack-ready.php"
  container_eval_file="/var/www/html/wp-content/plugins/${mounted_plugin_dir}/.wp-plugin-base-runtime-pack-smoke.php"

  WP_ENV_HOME="$wp_env_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" \
    wp_plugin_base_wordpress_env "$wp_env_tools_dir" run cli --config="$wp_env_config" -- \
    wp plugin activate "$plugin_entry" >/dev/null

  wp_eval_file="$fixture_dir/.wp-plugin-base-runtime-pack-smoke.php"

  cat > "$wp_eval_file" <<EOF
<?php
function wp_plugin_base_runtime_pack_smoke_fail( \$message ) {
  fwrite( STDERR, \$message . PHP_EOL );
  exit( 1 );
}

\$namespace = 'runtime-pack-ready/v1';
\$hook      = 'toplevel_page_runtime-pack-ready-admin-ui';

\$unauthenticated_response = rest_do_request( new WP_REST_Request( 'GET', '/' . \$namespace . '/settings' ) );
if ( 401 !== \$unauthenticated_response->get_status() ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected unauthenticated settings request to return 401.' );
}

wp_set_current_user( 1 );

\$read_response = rest_do_request( new WP_REST_Request( 'GET', '/' . \$namespace . '/settings' ) );
if ( 200 !== \$read_response->get_status() ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected authenticated settings read request to return 200.' );
}

\$read_payload = \$read_response->get_data();
if ( empty( \$read_payload['message'] ) ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected settings.read to return a message payload.' );
}

\$update_request = new WP_REST_Request( 'POST', '/' . \$namespace . '/settings' );
\$update_request->set_body_params(
  array(
    'message' => 'Updated from runtime pack smoke test (${variant_name})',
  )
);
\$update_response = rest_do_request( \$update_request );
if ( 200 !== \$update_response->get_status() ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected authenticated settings update request to return 200.' );
}

\$update_payload = \$update_response->get_data();
if ( empty( \$update_payload['updated'] ) || 'Updated from runtime pack smoke test (${variant_name})' !== \$update_payload['message'] ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected settings.update to persist the submitted message.' );
}

\$missing_update_request = new WP_REST_Request( 'POST', '/' . \$namespace . '/settings' );
\$missing_update_response = rest_do_request( \$missing_update_request );
if ( 400 !== \$missing_update_response->get_status() ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected missing required settings update payloads to return 400.' );
}

\$invalid_update_request = new WP_REST_Request( 'POST', '/' . \$namespace . '/settings' );
\$invalid_update_request->set_body_params(
  array(
    'message' => array( 'invalid' ),
  )
);
\$invalid_update_response = rest_do_request( \$invalid_update_request );
if ( 400 !== \$invalid_update_response->get_status() ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected invalid settings update payloads to return 400.' );
}

\$confirm_response = rest_do_request( new WP_REST_Request( 'GET', '/' . \$namespace . '/settings' ) );
\$confirm_payload  = \$confirm_response->get_data();
if ( 'Updated from runtime pack smoke test (${variant_name})' !== \$confirm_payload['message'] ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected persisted settings value to round-trip after update.' );
}

\$routes = rest_get_server()->get_routes();
if ( empty( \$routes['/' . \$namespace . '/settings'] ) ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected runtime pack settings route to be registered in the REST server.' );
}

do_action( 'admin_menu' );
if ( function_exists( 'set_current_screen' ) ) {
  set_current_screen( \$hook );
}
ob_start();
do_action( \$hook );
\$rendered_markup = ob_get_clean();
if ( false === strpos( \$rendered_markup, 'runtime-pack-ready-admin-ui-root' ) ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected admin page render output to include the managed root element.' );
}

remove_action( 'admin_enqueue_scripts', 'wp_enqueue_command_palette_assets' );
do_action( 'admin_enqueue_scripts', \$hook );
if ( ! wp_script_is( 'runtime-pack-ready-admin-ui', 'enqueued' ) ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected runtime pack admin script to be enqueued.' );
}

if ( ! wp_style_is( 'runtime-pack-ready-admin-ui', 'enqueued' ) ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected runtime pack admin style to be enqueued.' );
}

\$scripts = wp_scripts();
if ( empty( \$scripts->registered['runtime-pack-ready-admin-ui'] ) ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected runtime pack admin script to be registered.' );
}

\$registered_script = \$scripts->registered['runtime-pack-ready-admin-ui'];
if ( ! isset( \$registered_script->textdomain ) || 'runtime-pack-ready' !== \$registered_script->textdomain ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected runtime pack admin script translations to target the child plugin text domain.' );
}

\$inline_data = \$scripts->get_data( 'runtime-pack-ready-admin-ui', 'data' );
if ( ! is_string( \$inline_data ) || '' === \$inline_data ) {
  \$inline_data = \$scripts->get_data( 'runtime-pack-ready-admin-ui', 'before' );
  if ( is_array( \$inline_data ) ) {
    \$inline_data = implode( "\n", \$inline_data );
  }
}

if ( ! is_string( \$inline_data ) || false === strpos( \$inline_data, 'runtime-pack-ready' ) ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected runtime pack admin inline config to include the plugin slug payload.' );
}

if ( false === strpos( \$inline_data, '"experimentalDataViews":${enable_dataviews}' ) ) {
  wp_plugin_base_runtime_pack_smoke_fail( 'Expected runtime pack admin inline config to reflect the generated starter mode.' );
}

echo "Runtime pack WordPress smoke test passed for ${variant_name}." . PHP_EOL;
EOF

  WP_ENV_HOME="$wp_env_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" \
    wp_plugin_base_wordpress_env "$wp_env_tools_dir" run cli --config="$wp_env_config" -- \
    wp eval-file "$container_eval_file"

  WP_ENV_HOME="$wp_env_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" \
    wp_plugin_base_wordpress_env "$wp_env_tools_dir" stop --config="$wp_env_config" >/dev/null

  rm -rf "$fixture_dir" "$wp_env_config" 2>/dev/null || true
}

run_variant "basic" "false"
run_variant "dataviews" "true"

echo "Runtime pack WordPress smoke tests passed."
