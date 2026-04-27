#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

make_fixture() {
  local fixture_name="$1"
  local fixture_dir

  fixture_dir="$(mktemp -d)"
  cp -R "$ROOT_DIR/tests/fixtures/$fixture_name/." "$fixture_dir/"
  mkdir -p "$fixture_dir/.wp-plugin-base"
  rsync -a --exclude '.git' "$ROOT_DIR/" "$fixture_dir/.wp-plugin-base/"
  printf '%s\n' "$fixture_dir"
}

assert_regular_file() {
  local path="$1"
  local message="$2"

  if [ ! -f "$path" ]; then
    echo "$message" >&2
    exit 1
  fi
}

assert_not_present() {
  local path="$1"
  local message="$2"

  if [ -e "$path" ]; then
    echo "$message" >&2
    exit 1
  fi
}

full_fixture="$(make_fixture quality-ready)"
bridge_fixture="$(make_fixture standard-plugin)"
mode_only_fixture="$(make_fixture standard-plugin)"
trap 'rm -rf "$full_fixture" "$bridge_fixture" "$mode_only_fixture"' EXIT

WP_PLUGIN_BASE_ROOT="$full_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"

assert_regular_file "$full_fixture/.phpcs.xml.dist" "Full quality pack should manage .phpcs.xml.dist."
assert_regular_file "$full_fixture/phpstan.neon.dist" "Full quality pack should manage phpstan.neon.dist."
assert_regular_file "$full_fixture/phpunit.xml.dist" "Full quality pack should manage phpunit.xml.dist."
assert_regular_file "$full_fixture/phpstan.neon" "Full quality pack should seed phpstan.neon."
assert_regular_file "$full_fixture/tests/bootstrap.php" "Full quality pack should manage tests/bootstrap.php."
assert_regular_file "$full_fixture/tests/wp-plugin-base/bootstrap-child.php" "Full quality pack should seed bootstrap-child.php."
assert_regular_file "$full_fixture/tests/wp-plugin-base/BootstrapTest.php" "Full quality pack should manage the baseline bootstrap test."
assert_regular_file "$full_fixture/tests/wp-plugin-base/PluginLoadsTest.php" "Full quality pack should manage the baseline plugin load test."
assert_regular_file "$full_fixture/.wp-plugin-base-quality-pack/composer.json" "Full quality pack should manage composer.json."

grep -Fq "bootstrap-child.php" "$full_fixture/tests/bootstrap.php" || {
  echo "Managed quality-pack bootstrap should load the child-owned bootstrap overlay." >&2
  exit 1
}

wp_tests_dir="$full_fixture/wp-tests"
mkdir -p "$wp_tests_dir/includes"

cat > "$wp_tests_dir/includes/functions.php" <<'EOF_FUNCTIONS'
<?php
declare(strict_types=1);

function tests_add_filter($hook, $callback): void {
    file_put_contents((string) getenv('WP_PLUGIN_BASE_TEST_LOG'), $hook . PHP_EOL, FILE_APPEND);
}
EOF_FUNCTIONS

cat > "$wp_tests_dir/includes/bootstrap.php" <<'EOF_BOOTSTRAP'
<?php
declare(strict_types=1);
return;
EOF_BOOTSTRAP

cat > "$full_fixture/tests/wp-plugin-base/bootstrap-child.php" <<'EOF_CHILD'
<?php
declare(strict_types=1);

tests_add_filter(
    'child-overlay-loaded',
    static function (): void {}
);
EOF_CHILD

WP_PLUGIN_BASE_TEST_LOG="$full_fixture/bootstrap-child.log" \
WP_TESTS_DIR="$wp_tests_dir" \
php "$full_fixture/tests/bootstrap.php"

grep -Fq 'child-overlay-loaded' "$full_fixture/bootstrap-child.log" || {
  echo "Bootstrap child overlay should be able to register WordPress test hooks." >&2
  exit 1
}

printf '%s\n' '# preserve me' >> "$full_fixture/phpstan.neon"
printf '%s\n' '// preserve me' >> "$full_fixture/tests/wp-plugin-base/bootstrap-child.php"
WP_PLUGIN_BASE_ROOT="$full_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"

grep -Fq '# preserve me' "$full_fixture/phpstan.neon" || {
  echo "Seeded phpstan.neon should remain child-owned across sync." >&2
  exit 1
}

grep -Fq '// preserve me' "$full_fixture/tests/wp-plugin-base/bootstrap-child.php" || {
  echo "Seeded bootstrap-child.php should remain child-owned across sync." >&2
  exit 1
}

rm -f "$full_fixture/tests/wp-plugin-base/bootstrap-child.php"
if WP_PLUGIN_BASE_ROOT="$full_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Project validation unexpectedly passed with a missing quality-pack bootstrap overlay." >&2
  exit 1
fi

cat >> "$bridge_fixture/.wp-plugin-base.env" <<'EOF_CONFIG'
PHP_RUNTIME_MATRIX=8.1,8.2
PHP_RUNTIME_MATRIX_MODE=strict
EOF_CONFIG

WP_PLUGIN_BASE_ROOT="$bridge_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_PLUGIN_BASE_ROOT="$bridge_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" >/dev/null

assert_regular_file "$bridge_fixture/phpunit.xml.dist" "Strict runtime matrix should manage phpunit.xml.dist."
assert_regular_file "$bridge_fixture/tests/bootstrap.php" "Strict runtime matrix should manage tests/bootstrap.php."
assert_regular_file "$bridge_fixture/tests/wp-plugin-base/bootstrap-child.php" "Strict runtime matrix should seed bootstrap-child.php."
assert_regular_file "$bridge_fixture/tests/wp-plugin-base/BootstrapTest.php" "Strict runtime matrix should manage the baseline bootstrap test."
assert_regular_file "$bridge_fixture/tests/wp-plugin-base/PluginLoadsTest.php" "Strict runtime matrix should manage the baseline plugin load test."
assert_regular_file "$bridge_fixture/.wp-plugin-base-quality-pack/composer.json" "Strict runtime matrix should manage composer.json."
assert_regular_file "$bridge_fixture/.wp-plugin-base-quality-pack/composer.lock" "Strict runtime matrix should manage composer.lock."
assert_not_present "$bridge_fixture/.phpcs.xml.dist" "Strict runtime matrix should not force PHPCS config without the full quality pack."
assert_not_present "$bridge_fixture/phpstan.neon.dist" "Strict runtime matrix should not force PHPStan config without the full quality pack."
assert_not_present "$bridge_fixture/phpstan.neon" "Strict runtime matrix should not seed phpstan.neon without the full quality pack."

cat > "$bridge_fixture/tests/bootstrap.php" <<'EOF_CUSTOM_BOOTSTRAP'
<?php
declare(strict_types=1);

require_once __DIR__ . '/legacy-custom-preload.php';
EOF_CUSTOM_BOOTSTRAP

: > "$bridge_fixture/tests/wp-plugin-base/bootstrap-child.php"

sync_warning_output="$(
  WP_PLUGIN_BASE_ROOT="$bridge_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh" 2>&1
)"

printf '%s' "$sync_warning_output" | grep -Fq "tests/bootstrap.php is managed by wp-plugin-base and was customized in this repository." || {
  echo "Sync should warn when managed bootstrap customizations are detected without a child bootstrap overlay." >&2
  exit 1
}

printf '%s' "$sync_warning_output" | grep -Fq "tests/wp-plugin-base/bootstrap-child.php" || {
  echo "Sync warning should point to the child-owned bootstrap overlay path." >&2
  exit 1
}

cat >> "$mode_only_fixture/.wp-plugin-base.env" <<'EOF_CONFIG'
PHP_RUNTIME_MATRIX_MODE=strict
EOF_CONFIG

WP_PLUGIN_BASE_ROOT="$mode_only_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"

assert_not_present "$mode_only_fixture/phpunit.xml.dist" "Strict mode without a runtime matrix should not seed the PHPUnit bridge."
assert_not_present "$mode_only_fixture/tests/bootstrap.php" "Strict mode without a runtime matrix should not manage tests/bootstrap.php."
assert_not_present "$mode_only_fixture/.wp-plugin-base-quality-pack/composer.json" "Strict mode without a runtime matrix should not manage composer.json."

echo "Quality pack contract tests passed."
