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

wp_plugin_base_require_commands "WordPress quality pack" docker php
wp_plugin_base_load_config "$CONFIG_OVERRIDE"

if ! wp_plugin_base_is_true "$WORDPRESS_QUALITY_PACK_ENABLED"; then
  echo "WordPress quality pack is disabled; skipping."
  exit 0
fi

TOOLS_DIR="$ROOT_DIR/.wp-plugin-base-quality-pack"
COMPOSER_WORK_DIR="$(mktemp -d)"
COMPOSER_CACHE_DIR="$(mktemp -d)"
PHPSTAN_CONFIG="$COMPOSER_WORK_DIR/phpstan.neon"

cleanup() {
  rm -rf "$COMPOSER_WORK_DIR" "$COMPOSER_CACHE_DIR"
}

trap cleanup EXIT

for required_file in \
  "$ROOT_DIR/.phpcs.xml.dist" \
  "$ROOT_DIR/phpstan.neon.dist" \
  "$ROOT_DIR/phpunit.xml.dist" \
  "$ROOT_DIR/tests/bootstrap.php" \
  "$TOOLS_DIR/composer.lock" \
  "$TOOLS_DIR/composer.json"; do
  if [ ! -f "$required_file" ]; then
    echo "Missing managed quality pack file: $required_file" >&2
    exit 1
  fi
done

cp "$TOOLS_DIR/composer.json" "$TOOLS_DIR/composer.lock" "$COMPOSER_WORK_DIR/"

composer_install_command() {
  docker run --rm \
    -u "$(id -u):$(id -g)" \
    -e COMPOSER_CACHE_DIR=/tmp/composer-cache \
    -v "$COMPOSER_CACHE_DIR":/tmp/composer-cache \
    -v "$COMPOSER_WORK_DIR":/workspace \
    -w /workspace \
    "$WP_PLUGIN_BASE_COMPOSER_IMAGE" \
    install --no-interaction --no-progress --prefer-dist >/dev/null
}

wp_plugin_base_run_with_retry 3 2 "Quality pack Composer install" composer_install_command

docker run --rm \
  -u "$(id -u):$(id -g)" \
  -e COMPOSER_CACHE_DIR=/tmp/composer-cache \
  -v "$COMPOSER_CACHE_DIR":/tmp/composer-cache \
  -v "$COMPOSER_WORK_DIR":/workspace \
  -w /workspace \
  "$WP_PLUGIN_BASE_COMPOSER_IMAGE" \
  audit --locked --no-interaction --no-dev

cat > "$PHPSTAN_CONFIG" <<EOF
includes:
  - '$COMPOSER_WORK_DIR/vendor/szepeviktor/phpstan-wordpress/extension.neon'
  - '$ROOT_DIR/phpstan.neon.dist'

parameters:
  tmpDir: '$COMPOSER_WORK_DIR/phpstan-tmp'
EOF

php "$COMPOSER_WORK_DIR/vendor/bin/phpcs" --standard="$ROOT_DIR/.phpcs.xml.dist"
php "$COMPOSER_WORK_DIR/vendor/bin/phpstan" analyse --configuration="$PHPSTAN_CONFIG" --no-progress
php "$COMPOSER_WORK_DIR/vendor/bin/phpunit" --configuration="$ROOT_DIR/phpunit.xml.dist"

echo "Validated WordPress quality pack."
