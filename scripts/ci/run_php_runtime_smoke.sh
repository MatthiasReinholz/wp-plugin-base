#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"
# shellcheck source=../lib/quality_pack.sh
. "$SCRIPT_DIR/../lib/quality_pack.sh"
# shellcheck source=../lib/wordpress_tooling.sh
. "$SCRIPT_DIR/../lib/wordpress_tooling.sh"

CONFIG_OVERRIDE="${1:-}"
BRANCH_NAME="${2:-${BRANCH_NAME:-}}"
composer_work_dir=""
composer_cache_dir=""

wp_plugin_base_cleanup_runtime_smoke() {
  if [ -n "$composer_work_dir" ]; then
    rm -rf "$composer_work_dir"
  fi

  if [ -n "$composer_cache_dir" ]; then
    rm -rf "$composer_cache_dir"
  fi
}

trap wp_plugin_base_cleanup_runtime_smoke EXIT

wp_plugin_base_require_commands "PHP runtime smoke validation" git php node rsync zip unzip
bash "$SCRIPT_DIR/validate_config.sh" --scope ci "$CONFIG_OVERRIDE"
wp_plugin_base_load_config "$CONFIG_OVERRIDE"

if [ -z "$BRANCH_NAME" ] && git -C "$ROOT_DIR" symbolic-ref --quiet --short HEAD >/dev/null 2>&1; then
  BRANCH_NAME="$(git -C "$ROOT_DIR" symbolic-ref --quiet --short HEAD)"
fi

bash "$SCRIPT_DIR/validate_project.sh" "$CONFIG_OVERRIDE" "$BRANCH_NAME"

if wp_plugin_base_is_true "$WORDPRESS_READINESS_ENABLED"; then
  bash "$SCRIPT_DIR/validate_wordpress_metadata.sh" "$CONFIG_OVERRIDE"
fi

if [ "$PHP_RUNTIME_MATRIX_MODE" = "strict" ] && [ -f "$ROOT_DIR/phpunit.xml.dist" ] && [ -f "$ROOT_DIR/.wp-plugin-base-quality-pack/composer.json" ] && [ -f "$ROOT_DIR/.wp-plugin-base-quality-pack/composer.lock" ]; then
  if wp_plugin_base_docker_is_available; then
    composer_work_dir="$(mktemp -d)"
    composer_cache_dir="$(mktemp -d)"

    cp "$ROOT_DIR/.wp-plugin-base-quality-pack/composer.json" "$ROOT_DIR/.wp-plugin-base-quality-pack/composer.lock" "$composer_work_dir/"

    composer_install_command() {
      docker run --rm \
        -u "$(id -u):$(id -g)" \
        -e COMPOSER_CACHE_DIR=/tmp/composer-cache \
        -v "$composer_cache_dir":/tmp/composer-cache \
        -v "$composer_work_dir":/workspace \
        -w /workspace \
        "$WP_PLUGIN_BASE_COMPOSER_IMAGE" \
        install --no-interaction --no-progress --prefer-dist >/dev/null
    }

    wp_plugin_base_run_with_retry 3 2 "PHP runtime smoke Composer install" composer_install_command

    php "$composer_work_dir/vendor/bin/phpunit" --configuration="$ROOT_DIR/phpunit.xml.dist"
    rm -rf "$composer_work_dir" "$composer_cache_dir"
    # Disarm the EXIT trap for directories that were already removed.
    composer_work_dir=""
    composer_cache_dir=""
  elif wp_plugin_base_quality_pack_has_local_phpunit_bundle "$ROOT_DIR/.wp-plugin-base-quality-pack"; then
    echo "Docker is unavailable; using the installed local PHPUnit bridge bundle (strict runtime-matrix bridge mode, full quality pack optional)."
    php "$ROOT_DIR/.wp-plugin-base-quality-pack/vendor/bin/phpunit" --configuration="$ROOT_DIR/phpunit.xml.dist"
  else
    echo "PHP_RUNTIME_MATRIX_MODE=strict requires Docker or an installed local PHPUnit bridge bundle (bridge mode can run without the full quality pack)." >&2
    echo "Run composer install in .wp-plugin-base-quality-pack or start Docker." >&2
    exit 1
  fi
fi

echo "Validated PHP runtime smoke checks for $PLUGIN_SLUG on PHP $(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')."
