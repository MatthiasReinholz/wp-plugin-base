#!/usr/bin/env bash

set -euo pipefail

wp_plugin_base_quality_pack_is_full_enabled() {
  wp_plugin_base_is_true "${WORDPRESS_QUALITY_PACK_ENABLED:-false}"
}

wp_plugin_base_quality_pack_has_runtime_matrix() {
  [ -n "${PHP_RUNTIME_MATRIX:-}" ]
}

wp_plugin_base_quality_pack_phpunit_bridge_enabled() {
  [ "${PHP_RUNTIME_MATRIX_MODE:-smoke}" = "strict" ] && wp_plugin_base_quality_pack_has_runtime_matrix
}

wp_plugin_base_quality_pack_template_mode() {
  local relative_path="$1"

  case "$relative_path" in
    ".phpcs.xml.dist" | "phpstan.neon.dist")
      if wp_plugin_base_quality_pack_is_full_enabled; then
        printf 'full\n'
        return 0
      fi
      ;;
    ".wp-plugin-base-quality-pack/composer.json" | \
    ".wp-plugin-base-quality-pack/composer.lock" | \
    "phpunit.xml.dist" | \
    "tests/bootstrap.php" | \
    "tests/wp-plugin-base/PluginLoadsTest.php")
      if wp_plugin_base_quality_pack_is_full_enabled || wp_plugin_base_quality_pack_phpunit_bridge_enabled; then
        printf 'phpunit-bridge\n'
        return 0
      fi
      ;;
  esac

  return 1
}

wp_plugin_base_quality_pack_seed_mode() {
  local relative_path="$1"

  case "$relative_path" in
    "phpstan.neon")
      if wp_plugin_base_quality_pack_is_full_enabled; then
        printf 'full\n'
        return 0
      fi
      ;;
    "tests/wp-plugin-base/bootstrap-child.php")
      if wp_plugin_base_quality_pack_is_full_enabled || wp_plugin_base_quality_pack_phpunit_bridge_enabled; then
        printf 'phpunit-bridge\n'
        return 0
      fi
      ;;
  esac

  return 1
}

wp_plugin_base_docker_is_available() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

wp_plugin_base_quality_pack_has_local_phpunit_bundle() {
  local tools_dir="$1"

  [ -f "$tools_dir/vendor/bin/phpunit" ]
}

wp_plugin_base_quality_pack_has_local_full_bundle() {
  local tools_dir="$1"

  [ -f "$tools_dir/vendor/bin/phpcs" ] \
    && [ -f "$tools_dir/vendor/bin/phpstan" ] \
    && [ -f "$tools_dir/vendor/bin/phpunit" ] \
    && [ -f "$tools_dir/vendor/szepeviktor/phpstan-wordpress/extension.neon" ]
}
