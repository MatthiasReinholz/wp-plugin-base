#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"
# shellcheck source=../lib/quality_pack.sh
. "$SCRIPT_DIR/../lib/quality_pack.sh"
# shellcheck source=../lib/wordpress_tooling.sh
. "$SCRIPT_DIR/../lib/wordpress_tooling.sh"

wp_plugin_base_require_commands "quality-pack platform checks" php

if command -v composer >/dev/null 2>&1; then
  use_local_composer=true
elif wp_plugin_base_docker_is_available; then
  use_local_composer=false
else
  echo "Quality-pack platform checks require Composer or the supported Docker tooling." >&2
  exit 1
fi

FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT
cp "$ROOT_DIR/templates/child/quality-pack/.wp-plugin-base-quality-pack/"composer.{json,lock} "$FIXTURE_DIR/"

php -r '
$manifest = json_decode(file_get_contents($argv[1] . "/composer.json"), true, 512, JSON_THROW_ON_ERROR);
$lock = json_decode(file_get_contents($argv[1] . "/composer.lock"), true, 512, JSON_THROW_ON_ERROR);
if (($manifest["config"]["platform"]["php"] ?? null) !== "8.0.0"
    || ($lock["platform-overrides"]["php"] ?? null) !== "8.0.0"
    || ($manifest["config"]["platform-check"] ?? true) === false) {
    fwrite(STDERR, "The quality pack must retain its PHP 8.0 dependency floor and platform checks.\n");
    exit(1);
}
' "$FIXTURE_DIR"

check_locked_platform() {
  local install_args=(install --dry-run --no-interaction --no-progress --no-scripts --no-plugins)

  if [ "$use_local_composer" = true ]; then
    COMPOSER_DISABLE_NETWORK=1 COMPOSER_CACHE_DIR="$FIXTURE_DIR/cache" \
      composer --working-dir="$FIXTURE_DIR" "${install_args[@]}" >"$FIXTURE_DIR/install.log" 2>&1
  else
    docker run --rm --network none \
      -u "$(id -u):$(id -g)" \
      -e COMPOSER_DISABLE_NETWORK=1 \
      -e COMPOSER_CACHE_DIR=/workspace/cache \
      -v "$FIXTURE_DIR":/workspace -w /workspace \
      "$WP_PLUGIN_BASE_COMPOSER_IMAGE" "${install_args[@]}" >"$FIXTURE_DIR/install.log" 2>&1
  fi
}

if ! check_locked_platform; then
  cat "$FIXTURE_DIR/install.log" >&2
  exit 1
fi

# An install on a newer build image must not hide a locked dependency that cannot
# execute on a supported child interpreter. Exercise Composer's real solver.
php -r '
$path = $argv[1] . "/composer.lock";
$lock = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
foreach ($lock["packages-dev"] as &$package) {
    if ($package["name"] === "doctrine/instantiator") {
        $package["require"]["php"] = "^8.1";
        file_put_contents($path, json_encode($lock, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
        exit(0);
    }
}
fwrite(STDERR, "Missing dependency used by the incompatible-platform regression.\n");
exit(1);
' "$FIXTURE_DIR"

if check_locked_platform; then
  echo "Composer accepted a locked dependency incompatible with the supported PHP floor." >&2
  exit 1
fi

grep -Fq 'requires php ^8.1' "$FIXTURE_DIR/install.log" || {
  cat "$FIXTURE_DIR/install.log" >&2
  echo "The incompatible lock failed for an unexpected reason." >&2
  exit 1
}

echo "Quality-pack PHP platform contract tests passed."
