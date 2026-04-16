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

cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$FIXTURE_DIR/"
mkdir -p "$FIXTURE_DIR/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$FIXTURE_DIR/.wp-plugin-base/"

cat >> "$FIXTURE_DIR/.wp-plugin-base.env" <<'EOF_CONFIG'
PHP_RUNTIME_MATRIX=8.1
PHP_RUNTIME_MATRIX_MODE=strict
EOF_CONFIG

WP_PLUGIN_BASE_ROOT="$FIXTURE_DIR" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"

mkdir -p "$FIXTURE_DIR/.wp-plugin-base-quality-pack/vendor/bin"

cat > "$FIXTURE_DIR/.wp-plugin-base-quality-pack/vendor/bin/phpunit" <<'EOF_PHP'
<?php
declare(strict_types=1);
file_put_contents((string) getenv('WP_PLUGIN_BASE_TEST_LOG'), "phpunit\n", FILE_APPEND);
EOF_PHP

cat > "$FAKE_BIN_DIR/docker" <<'EOF_DOCKER'
#!/usr/bin/env bash
exit 1
EOF_DOCKER

chmod +x "$FAKE_BIN_DIR/docker"

PATH="$FAKE_BIN_DIR:$PATH" \
WP_PLUGIN_BASE_ROOT="$FIXTURE_DIR" \
WP_PLUGIN_BASE_TEST_LOG="$LOG_FILE" \
bash "$ROOT_DIR/scripts/ci/run_php_runtime_smoke.sh" "" "feature/phpunit-bridge" >/dev/null

grep -Fxq 'phpunit' "$LOG_FILE" || {
  echo "Strict runtime smoke should use the installed local PHPUnit bridge when Docker is unavailable." >&2
  cat "$LOG_FILE" >&2
  exit 1
}

echo "PHP runtime smoke local fallback tests passed."
