#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE_CONFIG="$ROOT_DIR/scripts/ci/validate_config.sh"
VALIDATE_CONFIG_CONTRACT="$ROOT_DIR/scripts/ci/validate_config_contract.sh"

make_fixture() {
  local fixture_dir

  fixture_dir="$(mktemp -d)"
  cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$fixture_dir/"
  printf '%s\n' "$fixture_dir"
}

write_base_config() {
  local config_path="$1"

  cat > "$config_path" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.5.0
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG
}

expect_validation_failure() {
  local fixture_dir="$1"
  local config_file="$2"
  local expected_message="$3"
  local output_file="$fixture_dir/validate-config-output.log"

  if WP_PLUGIN_BASE_ROOT="$fixture_dir" bash "$VALIDATE_CONFIG" --scope project "$config_file" >"$output_file" 2>&1; then
    echo "Config validation unexpectedly passed for $config_file." >&2
    cat "$output_file" >&2
    exit 1
  fi

  if ! grep -Fq "$expected_message" "$output_file"; then
    echo "Config validation failed for $config_file, but did not emit the expected message." >&2
    echo "Expected: $expected_message" >&2
    echo "Actual output:" >&2
    cat "$output_file" >&2
    exit 1
  fi
}

bash "$VALIDATE_CONFIG_CONTRACT" >/dev/null

defaults_fixture="$(make_fixture)"
abilities_fixture="$(make_fixture)"
admin_fixture="$(make_fixture)"
dataviews_fixture="$(make_fixture)"
starter_fixture="$(make_fixture)"
conflict_fixture="$(make_fixture)"
trap 'rm -rf "$defaults_fixture" "$abilities_fixture" "$admin_fixture" "$dataviews_fixture" "$starter_fixture" "$conflict_fixture"' EXIT

write_base_config "$defaults_fixture/.defaults.env"
cat >> "$defaults_fixture/.defaults.env" <<'EOF_CONFIG'
REST_OPERATIONS_PACK_ENABLED=true
ADMIN_UI_PACK_ENABLED=true
BUILD_SCRIPT=.wp-plugin-base-admin-ui/build.sh
EOF_CONFIG
WP_PLUGIN_BASE_ROOT="$defaults_fixture" bash "$VALIDATE_CONFIG" --scope project .defaults.env >/dev/null

write_base_config "$abilities_fixture/.abilities.env"
cat >> "$abilities_fixture/.abilities.env" <<'EOF_CONFIG'
REST_ABILITIES_ENABLED=true
EOF_CONFIG
expect_validation_failure \
  "$abilities_fixture" \
  .abilities.env \
  'REST_ABILITIES_ENABLED=true requires REST_OPERATIONS_PACK_ENABLED=true.'

write_base_config "$admin_fixture/.admin-ui.env"
cat >> "$admin_fixture/.admin-ui.env" <<'EOF_CONFIG'
ADMIN_UI_PACK_ENABLED=true
BUILD_SCRIPT=.wp-plugin-base-admin-ui/build.sh
EOF_CONFIG
expect_validation_failure \
  "$admin_fixture" \
  .admin-ui.env \
  'ADMIN_UI_PACK_ENABLED=true requires REST_OPERATIONS_PACK_ENABLED=true.'

write_base_config "$dataviews_fixture/.dataviews.env"
cat >> "$dataviews_fixture/.dataviews.env" <<'EOF_CONFIG'
ADMIN_UI_EXPERIMENTAL_DATAVIEWS=true
EOF_CONFIG
expect_validation_failure \
  "$dataviews_fixture" \
  .dataviews.env \
  'ADMIN_UI_EXPERIMENTAL_DATAVIEWS=true requires ADMIN_UI_PACK_ENABLED=true.'

write_base_config "$starter_fixture/.starter.env"
cat >> "$starter_fixture/.starter.env" <<'EOF_CONFIG'
ADMIN_UI_STARTER=dataviews
EOF_CONFIG
expect_validation_failure \
  "$starter_fixture" \
  .starter.env \
  'ADMIN_UI_STARTER requires ADMIN_UI_PACK_ENABLED=true.'

write_base_config "$conflict_fixture/.conflict.env"
cat >> "$conflict_fixture/.conflict.env" <<'EOF_CONFIG'
REST_OPERATIONS_PACK_ENABLED=true
ADMIN_UI_PACK_ENABLED=true
BUILD_SCRIPT=.wp-plugin-base-admin-ui/build.sh
ADMIN_UI_STARTER=basic
ADMIN_UI_EXPERIMENTAL_DATAVIEWS=true
EOF_CONFIG
expect_validation_failure \
  "$conflict_fixture" \
  .conflict.env \
  'ADMIN_UI_STARTER=basic conflicts with ADMIN_UI_EXPERIMENTAL_DATAVIEWS=true. Use ADMIN_UI_STARTER=dataviews or unset the legacy flag.'

echo "Config runtime-pack contract tests passed."
