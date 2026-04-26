#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_DIR="$(mktemp -d)"
FAKE_BIN_DIR="$(mktemp -d)"
LOG_FILE="$(mktemp)"

cleanup() {
  rm -rf "$FIXTURE_DIR" "$FAKE_BIN_DIR" "$LOG_FILE"
}

trap cleanup EXIT

cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$FIXTURE_DIR/"
mkdir -p "$FIXTURE_DIR/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$FIXTURE_DIR/.wp-plugin-base/"

WP_PLUGIN_BASE_ROOT="$FIXTURE_DIR" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
printf '%s\n' '# local phpstan overlay' >> "$FIXTURE_DIR/phpstan.neon"

mkdir -p \
  "$FIXTURE_DIR/.wp-plugin-base-quality-pack/vendor/bin" \
  "$FIXTURE_DIR/.wp-plugin-base-quality-pack/vendor/szepeviktor/phpstan-wordpress"

cat > "$FIXTURE_DIR/.wp-plugin-base-quality-pack/vendor/bin/phpcs" <<'EOF_PHP'
<?php
declare(strict_types=1);
file_put_contents((string) getenv('WP_PLUGIN_BASE_TEST_LOG'), "phpcs\n", FILE_APPEND);
EOF_PHP

cat > "$FIXTURE_DIR/.wp-plugin-base-quality-pack/vendor/bin/phpstan" <<'EOF_PHP'
<?php
declare(strict_types=1);

$configPath = null;
foreach ($argv as $arg) {
    if (0 === strpos($arg, '--configuration=')) {
        $configPath = substr($arg, strlen('--configuration='));
        break;
    }
}

if (! $configPath || ! file_exists($configPath)) {
    fwrite(STDERR, "PHPStan fallback test did not receive a readable configuration file.\n");
    exit(1);
}

$configContents = (string) file_get_contents($configPath);
$expectedDist = (string) getenv('WP_PLUGIN_BASE_TEST_EXPECTED_PHPSTAN_DIST');
$expectedOverlay = (string) getenv('WP_PLUGIN_BASE_TEST_EXPECTED_PHPSTAN_OVERLAY');

if (false === strpos($configContents, $expectedDist)) {
    fwrite(STDERR, "Generated PHPStan config did not include phpstan.neon.dist.\n");
    exit(1);
}

if (false === strpos($configContents, $expectedOverlay)) {
    fwrite(STDERR, "Generated PHPStan config did not include the child-owned phpstan.neon overlay.\n");
    exit(1);
}

file_put_contents((string) getenv('WP_PLUGIN_BASE_TEST_LOG'), "phpstan\n", FILE_APPEND);
EOF_PHP

cat > "$FIXTURE_DIR/.wp-plugin-base-quality-pack/vendor/bin/phpunit" <<'EOF_PHP'
<?php
declare(strict_types=1);
file_put_contents((string) getenv('WP_PLUGIN_BASE_TEST_LOG'), "phpunit\n", FILE_APPEND);
EOF_PHP

touch "$FIXTURE_DIR/.wp-plugin-base-quality-pack/vendor/szepeviktor/phpstan-wordpress/extension.neon"

cat > "$FAKE_BIN_DIR/composer" <<'EOF_COMPOSER'
#!/usr/bin/env bash
set -euo pipefail
printf 'composer:%s\n' "$*" >> "$WP_PLUGIN_BASE_TEST_LOG"
EOF_COMPOSER

cat > "$FAKE_BIN_DIR/docker" <<'EOF_DOCKER'
#!/usr/bin/env bash
exit 1
EOF_DOCKER

chmod +x "$FAKE_BIN_DIR/composer" "$FAKE_BIN_DIR/docker"

PATH="$FAKE_BIN_DIR:$PATH" \
WP_PLUGIN_BASE_ROOT="$FIXTURE_DIR" \
WP_PLUGIN_BASE_TEST_LOG="$LOG_FILE" \
WP_PLUGIN_BASE_TEST_EXPECTED_PHPSTAN_DIST="$FIXTURE_DIR/phpstan.neon.dist" \
WP_PLUGIN_BASE_TEST_EXPECTED_PHPSTAN_OVERLAY="$FIXTURE_DIR/phpstan.neon" \
bash "$ROOT_DIR/scripts/ci/run_quality_pack.sh" >/dev/null

grep -Fq 'composer:--working-dir=' "$LOG_FILE" || {
  echo "Local quality-pack fallback should call composer." >&2
  cat "$LOG_FILE" >&2
  exit 1
}

grep -Fq '.wp-plugin-base-quality-pack audit --locked --no-interaction' "$LOG_FILE" || {
  echo "Local quality-pack fallback should run composer audit from the installed bundle." >&2
  cat "$LOG_FILE" >&2
  exit 1
}

grep -Fxq 'phpcs' "$LOG_FILE" || {
  echo "Local quality-pack fallback should execute PHPCS from the installed bundle." >&2
  cat "$LOG_FILE" >&2
  exit 1
}

grep -Fxq 'phpstan' "$LOG_FILE" || {
  echo "Local quality-pack fallback should execute PHPStan from the installed bundle." >&2
  cat "$LOG_FILE" >&2
  exit 1
}

grep -Fxq 'phpunit' "$LOG_FILE" || {
  echo "Local quality-pack fallback should execute PHPUnit from the installed bundle." >&2
  cat "$LOG_FILE" >&2
  exit 1
}

echo "Quality pack local fallback tests passed."
