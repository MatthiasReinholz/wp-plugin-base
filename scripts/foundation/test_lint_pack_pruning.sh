#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fixture_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$fixture_dir"
}
trap cleanup EXIT

cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$fixture_dir/"
mkdir -p "$fixture_dir/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$fixture_dir/.wp-plugin-base/"

cat >> "$fixture_dir/.wp-plugin-base.env" <<'EOF'
WORDPRESS_QUALITY_PACK_ENABLED=false
WORDPRESS_SECURITY_PACK_ENABLED=false
EOF

WP_PLUGIN_BASE_ROOT="$fixture_dir" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"

mkdir -p "$fixture_dir/.wp-plugin-base-quality-pack/vendor/squizlabs/php_codesniffer/src/Standards/Generic/Tests/Commenting"
cat > "$fixture_dir/.wp-plugin-base-quality-pack/vendor/squizlabs/php_codesniffer/src/Standards/Generic/Tests/Commenting/DocCommentUnitTest.2.js" <<'EOF'
/** No docblock close tag. Must be last test without new line.
EOF

mkdir -p "$fixture_dir/.wp-plugin-base-security-pack/vendor/example"
cat > "$fixture_dir/.wp-plugin-base-security-pack/vendor/example/InvalidFixture.php" <<'EOF'
<?php

function lint_fixture_failure(
EOF

WP_PLUGIN_BASE_ROOT="$fixture_dir" bash "$ROOT_DIR/scripts/ci/lint_js.sh" ".wp-plugin-base.env"
WP_PLUGIN_BASE_ROOT="$fixture_dir" bash "$ROOT_DIR/scripts/ci/lint_php.sh" ".wp-plugin-base.env"

echo "Lint traversal pack-pruning regression test passed."
