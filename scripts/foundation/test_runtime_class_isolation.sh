#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
for name in legacy alpha beta; do
  consumer="$fixture/$name"
  mkdir -p "$consumer/.wp-plugin-base"
  cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$consumer/"
  rsync -a --exclude .git "$ROOT_DIR/" "$consumer/.wp-plugin-base/"
  perl -pi -e "s/^PLUGIN_SLUG=.*/PLUGIN_SLUG=$name/; s~^REST_API_NAMESPACE=.*~REST_API_NAMESPACE=$name/v1~" "$consumer/.wp-plugin-base.env"
  if [ "$name" != legacy ]; then
    printf '\nRUNTIME_CLASS_PREFIX=%s_\n' "$name" >> "$consumer/.wp-plugin-base.env"
  fi
  WP_PLUGIN_BASE_ROOT="$consumer" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh" >/dev/null
  WP_PLUGIN_BASE_ROOT="$consumer" bash "$ROOT_DIR/scripts/ci/scan_rest_operation_contract.sh" >/dev/null
  WP_PLUGIN_BASE_ROOT="$consumer" bash "$ROOT_DIR/scripts/ci/write_config_outputs.sh" project "$consumer/.wp-plugin-base.env" "$consumer/outputs" >/dev/null
  expected_prefix=''
  if [ "$name" != legacy ]; then expected_prefix="${name}_"; fi
  grep -Fxq "runtime_class_prefix=$expected_prefix" "$consumer/outputs"
  cp "$consumer/lib/wp-plugin-base/admin-ui/class-wp-plugin-base-admin-ui-loader.php" "$consumer/first-loader.php"
  printf '\n// Consumer-owned customization.\n' >> "$consumer/includes/admin-ui/bootstrap.php"
  WP_PLUGIN_BASE_ROOT="$consumer" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh" >/dev/null
  cmp "$consumer/first-loader.php" "$consumer/lib/wp-plugin-base/admin-ui/class-wp-plugin-base-admin-ui-loader.php"
  grep -Fq 'Consumer-owned customization.' "$consumer/includes/admin-ui/bootstrap.php"
  find "$consumer/lib/wp-plugin-base/rest-operations" "$consumer/lib/wp-plugin-base/admin-ui" "$consumer/includes" -name '*.php' -exec php -l {} \; >/dev/null
  mkdir -p "$consumer/assets/admin-ui"
  printf '/* %s */\n' "$name" > "$consumer/assets/admin-ui/index.js"
  printf '/* %s */\n' "$name" > "$consumer/assets/admin-ui/style-index.css"
done
# Bad PHP identifier prefixes must never reach the renderer.
cp "$fixture/alpha/.wp-plugin-base.env" "$fixture/invalid.env"
for bad in '1Bad_' 'Bad-Name_' 'NoTrailingUnderscore' 'Bad\\Namespace_'; do
  BAD_PREFIX="$bad" perl -pi -e 's/^RUNTIME_CLASS_PREFIX=.*/RUNTIME_CLASS_PREFIX=$ENV{BAD_PREFIX}/' "$fixture/invalid.env"
  if WP_PLUGIN_BASE_ROOT="$fixture/alpha" bash "$ROOT_DIR/scripts/ci/validate_config.sh" --scope project "$fixture/invalid.env" >/dev/null 2>&1; then
    echo "Invalid runtime class prefix accepted: $bad" >&2
    exit 1
  fi
done
FIXTURE="$fixture" php <<'PHP'
<?php
define('ABSPATH', '/');
$actions = $scripts = $styles = $inline = $routes = array();
function __( $value ) { return $value; }
function is_admin() { return true; }
function current_user_can( $capability ) { return true; }
function wp_json_encode( $value ) { return json_encode($value); }
function get_option( $key, $default = false ) { return $key; }
function add_action( $hook, $callback ) { $GLOBALS['actions'][$hook][] = $callback; }
function add_menu_page( $title, $menu, $cap, $slug, $callback ) { return $slug; }
function plugins_url( $path, $plugin ) { return dirname($plugin) . '/' . $path; }
function wp_enqueue_script( $handle, $url ) { $GLOBALS['scripts'][$handle][] = $url; }
function wp_enqueue_style( $handle, $url ) { $GLOBALS['styles'][$handle][] = $url; }
function wp_add_inline_script( $handle, $value ) { $GLOBALS['inline'][$handle][] = $value; }
function register_rest_route( $namespace, $route, $args ) { $GLOBALS['routes'][$namespace][] = $args; }
function check( $condition, $message ) { if (!$condition) throw new RuntimeException($message); }
foreach (array('legacy', 'alpha', 'beta') as $name) {
    require getenv('FIXTURE') . '/' . $name . '/lib/wp-plugin-base/rest-operations/bootstrap.php';
    require getenv('FIXTURE') . '/' . $name . '/lib/wp-plugin-base/admin-ui/bootstrap.php';
}
// Load all registries only after every bootstrap, exposing cross-plugin overwrite bugs.
foreach (array('legacy', 'alpha', 'beta') as $name) {
    $prefix = $name === 'legacy' ? '' : $name . '_';
    $registry = $prefix . 'WP_Plugin_Base_REST_Operations_Registry';
    $operations = $registry::all();
    check(count($operations) === 3, $name . ' lost its operation manifests');
    $settings = array_values(array_filter($operations, static fn($op) => $op['id'] === 'settings.read'))[0];
    check($settings['callback'] === $prefix . 'wp_plugin_base_example_rest_operation_get_settings', 'Seed callbacks not isolated');
    check($settings['callback'](null, array())['message'] === $name . '_admin_message', 'Callback read another plugin option');
}
alpha_WP_Plugin_Base_REST_Operations_Registry::register(array('id'=>'alpha.only','route'=>'/alpha-only','methods'=>'GET','callback'=>'alpha_wp_plugin_base_example_rest_operation_get_settings'));
check(count(beta_WP_Plugin_Base_REST_Operations_Registry::all()) === 3, 'Registries share state');
foreach ($actions['admin_menu'] as $callback) $callback();
foreach (array('legacy', 'alpha', 'beta') as $name) {
    foreach ($actions['admin_enqueue_scripts'] as $callback) $callback($name . '-admin-ui');
    check($scripts[$name . '-admin-ui'] === array(getenv('FIXTURE') . '/' . $name . '/assets/admin-ui/index.js'), 'Admin script resolved another consumer path or enqueued twice');
    check($styles[$name . '-admin-ui'] === array(getenv('FIXTURE') . '/' . $name . '/assets/admin-ui/style-index.css'), 'Admin style resolved another consumer path');
    check(count($inline[$name . '-admin-ui']) === 1, 'Admin bootstrap duplicated');
    check(str_contains($inline[$name . '-admin-ui'][0], 'alpha.only') === ($name === 'alpha'), 'Admin bootstrap reads another registry');
}
foreach ($actions['rest_api_init'] as $callback) $callback();
foreach (array('legacy', 'alpha', 'beta') as $name) check(count($routes[$name . '/v1']) === ($name === 'alpha' ? 4 : 3), 'Routes were overwritten across namespaces');
echo "Runtime packs coexist with isolated classes, callbacks, registries and asset paths.\n";
PHP
