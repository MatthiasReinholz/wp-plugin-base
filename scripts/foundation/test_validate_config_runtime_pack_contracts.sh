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
readiness_missing_fixture="$(make_fixture)"
readiness_strict_fixture="$(make_fixture)"
readiness_filtered_fixture="$(make_fixture)"
readiness_reduced_audit_fixture="$(make_fixture)"
readiness_invalid_audit_fixture="$(make_fixture)"
readiness_pass_fixture="$(make_fixture)"
phpstan_memory_invalid_fixture="$(make_fixture)"
phpstan_memory_pass_fixture="$(make_fixture)"
runtime_url_secret_fixture="$(make_fixture)"
runtime_url_private_fixture="$(make_fixture)"
runtime_url_cgnat_fixture="$(make_fixture)"
runtime_url_single_label_fixture="$(make_fixture)"
automation_api_secret_fixture="$(make_fixture)"
legacy_updater_secret_fixture="$(make_fixture)"
runtime_url_pass_fixture="$(make_fixture)"
trap 'rm -rf "$defaults_fixture" "$abilities_fixture" "$admin_fixture" "$dataviews_fixture" "$starter_fixture" "$conflict_fixture" "$readiness_missing_fixture" "$readiness_strict_fixture" "$readiness_filtered_fixture" "$readiness_reduced_audit_fixture" "$readiness_invalid_audit_fixture" "$readiness_pass_fixture" "$phpstan_memory_invalid_fixture" "$phpstan_memory_pass_fixture" "$runtime_url_secret_fixture" "$runtime_url_private_fixture" "$runtime_url_cgnat_fixture" "$runtime_url_single_label_fixture" "$automation_api_secret_fixture" "$legacy_updater_secret_fixture" "$runtime_url_pass_fixture"' EXIT

runtime_secret_url='https:'
runtime_secret_url="${runtime_secret_url}//updates.example.com/standard-plugin.json?token=secret"
runtime_private_url='https:'
runtime_private_url="${runtime_private_url}//127.0.0.1/standard-plugin.json"
runtime_cgnat_url='https:'
runtime_cgnat_url="${runtime_cgnat_url}//100.64.0.10/standard-plugin.json"
runtime_single_label_url='https:'
runtime_single_label_url="${runtime_single_label_url}//updates/standard-plugin.json"
automation_api_secret_url='https:'
automation_api_secret_url="${automation_api_secret_url}//api.github.com/api/v3?token=secret"
legacy_updater_secret_url='https:'
legacy_updater_secret_url="${legacy_updater_secret_url}//github.com/example/standard-plugin#token"
runtime_pass_url='https:'
runtime_pass_url="${runtime_pass_url}//updates.example.com/standard-plugin.json"

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

write_base_config "$readiness_missing_fixture/.readiness-missing.env"
cat >> "$readiness_missing_fixture/.readiness-missing.env" <<'EOF_CONFIG'
RELEASE_READINESS_MODE=security-sensitive
EOF_CONFIG
expect_validation_failure \
  "$readiness_missing_fixture" \
  .readiness-missing.env \
  'RELEASE_READINESS_MODE=security-sensitive requires WORDPRESS_READINESS_ENABLED=true, WORDPRESS_QUALITY_PACK_ENABLED=true, and WORDPRESS_SECURITY_PACK_ENABLED=true.'

write_base_config "$readiness_strict_fixture/.readiness-strict.env"
cat >> "$readiness_strict_fixture/.readiness-strict.env" <<'EOF_CONFIG'
WORDPRESS_READINESS_ENABLED=true
WORDPRESS_QUALITY_PACK_ENABLED=true
WORDPRESS_SECURITY_PACK_ENABLED=true
RELEASE_READINESS_MODE=security-sensitive
EOF_CONFIG
expect_validation_failure \
  "$readiness_strict_fixture" \
  .readiness-strict.env \
  'RELEASE_READINESS_MODE=security-sensitive requires WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS=true.'

write_base_config "$readiness_filtered_fixture/.readiness-filtered.env"
cat >> "$readiness_filtered_fixture/.readiness-filtered.env" <<'EOF_CONFIG'
WORDPRESS_READINESS_ENABLED=true
WORDPRESS_QUALITY_PACK_ENABLED=true
WORDPRESS_SECURITY_PACK_ENABLED=true
RELEASE_READINESS_MODE=security-sensitive
WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS=true
WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES=plugin_repo
EOF_CONFIG
expect_validation_failure \
  "$readiness_filtered_fixture" \
  .readiness-filtered.env \
  'RELEASE_READINESS_MODE=security-sensitive requires full Plugin Check coverage.'

write_base_config "$readiness_reduced_audit_fixture/.readiness-reduced-audit.env"
cat >> "$readiness_reduced_audit_fixture/.readiness-reduced-audit.env" <<'EOF_CONFIG'
WORDPRESS_READINESS_ENABLED=true
WORDPRESS_QUALITY_PACK_ENABLED=true
WORDPRESS_SECURITY_PACK_ENABLED=true
RELEASE_READINESS_MODE=security-sensitive
WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS=true
ADMIN_UI_NPM_AUDIT_LEVEL=critical
EOF_CONFIG
expect_validation_failure \
  "$readiness_reduced_audit_fixture" \
  .readiness-reduced-audit.env \
  'RELEASE_READINESS_MODE=security-sensitive requires ADMIN_UI_NPM_AUDIT_LEVEL=high.'

write_base_config "$readiness_invalid_audit_fixture/.readiness-invalid-audit.env"
cat >> "$readiness_invalid_audit_fixture/.readiness-invalid-audit.env" <<'EOF_CONFIG'
ADMIN_UI_NPM_AUDIT_LEVEL=moderate
EOF_CONFIG
expect_validation_failure \
  "$readiness_invalid_audit_fixture" \
  .readiness-invalid-audit.env \
  'Invalid ADMIN_UI_NPM_AUDIT_LEVEL: moderate'

write_base_config "$readiness_pass_fixture/.readiness-pass.env"
cat >> "$readiness_pass_fixture/.readiness-pass.env" <<'EOF_CONFIG'
WORDPRESS_READINESS_ENABLED=true
WORDPRESS_QUALITY_PACK_ENABLED=true
WORDPRESS_SECURITY_PACK_ENABLED=true
RELEASE_READINESS_MODE=security-sensitive
WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS=true
EOF_CONFIG
WP_PLUGIN_BASE_ROOT="$readiness_pass_fixture" bash "$VALIDATE_CONFIG" --scope project .readiness-pass.env >/dev/null

write_base_config "$phpstan_memory_invalid_fixture/.phpstan-memory-invalid.env"
cat >> "$phpstan_memory_invalid_fixture/.phpstan-memory-invalid.env" <<'EOF_CONFIG'
PHPSTAN_MEMORY_LIMIT=lots
EOF_CONFIG
expect_validation_failure \
  "$phpstan_memory_invalid_fixture" \
  .phpstan-memory-invalid.env \
  'Invalid PHPSTAN_MEMORY_LIMIT: lots'

write_base_config "$phpstan_memory_pass_fixture/.phpstan-memory-pass.env"
cat >> "$phpstan_memory_pass_fixture/.phpstan-memory-pass.env" <<'EOF_CONFIG'
PHPSTAN_MEMORY_LIMIT=768M
EOF_CONFIG
WP_PLUGIN_BASE_ROOT="$phpstan_memory_pass_fixture" bash "$VALIDATE_CONFIG" --scope project .phpstan-memory-pass.env >/dev/null

write_base_config "$runtime_url_secret_fixture/.runtime-url-secret.env"
cat >> "$runtime_url_secret_fixture/.runtime-url-secret.env" <<EOF_CONFIG
PLUGIN_RUNTIME_UPDATE_PROVIDER=generic-json
PLUGIN_RUNTIME_UPDATE_SOURCE_URL=${runtime_secret_url}
EOF_CONFIG
expect_validation_failure \
  "$runtime_url_secret_fixture" \
  .runtime-url-secret.env \
  "PLUGIN_RUNTIME_UPDATE_SOURCE_URL must not include query strings or fragments: ${runtime_secret_url}"

write_base_config "$runtime_url_private_fixture/.runtime-url-private.env"
cat >> "$runtime_url_private_fixture/.runtime-url-private.env" <<EOF_CONFIG
PLUGIN_RUNTIME_UPDATE_PROVIDER=generic-json
PLUGIN_RUNTIME_UPDATE_SOURCE_URL=${runtime_private_url}
EOF_CONFIG
expect_validation_failure \
  "$runtime_url_private_fixture" \
  .runtime-url-private.env \
  'PLUGIN_RUNTIME_UPDATE_SOURCE_URL must not use localhost, private-network, link-local, or *.internal hosts: 127.0.0.1'

write_base_config "$runtime_url_cgnat_fixture/.runtime-url-cgnat.env"
cat >> "$runtime_url_cgnat_fixture/.runtime-url-cgnat.env" <<EOF_CONFIG
PLUGIN_RUNTIME_UPDATE_PROVIDER=generic-json
PLUGIN_RUNTIME_UPDATE_SOURCE_URL=${runtime_cgnat_url}
EOF_CONFIG
expect_validation_failure \
  "$runtime_url_cgnat_fixture" \
  .runtime-url-cgnat.env \
  'PLUGIN_RUNTIME_UPDATE_SOURCE_URL must not use localhost, private-network, link-local, or *.internal hosts: 100.64.0.10'

write_base_config "$runtime_url_single_label_fixture/.runtime-url-single-label.env"
cat >> "$runtime_url_single_label_fixture/.runtime-url-single-label.env" <<EOF_CONFIG
PLUGIN_RUNTIME_UPDATE_PROVIDER=generic-json
PLUGIN_RUNTIME_UPDATE_SOURCE_URL=${runtime_single_label_url}
EOF_CONFIG
expect_validation_failure \
  "$runtime_url_single_label_fixture" \
  .runtime-url-single-label.env \
  'PLUGIN_RUNTIME_UPDATE_SOURCE_URL must not use localhost, private-network, link-local, or *.internal hosts: updates'

write_base_config "$automation_api_secret_fixture/.automation-api-secret.env"
cat >> "$automation_api_secret_fixture/.automation-api-secret.env" <<EOF_CONFIG
AUTOMATION_API_BASE=${automation_api_secret_url}
EOF_CONFIG
expect_validation_failure \
  "$automation_api_secret_fixture" \
  .automation-api-secret.env \
  "AUTOMATION_API_BASE must not include query strings or fragments: ${automation_api_secret_url}"

write_base_config "$legacy_updater_secret_fixture/.legacy-updater-secret.env"
cat >> "$legacy_updater_secret_fixture/.legacy-updater-secret.env" <<EOF_CONFIG
GITHUB_RELEASE_UPDATER_REPO_URL=${legacy_updater_secret_url}
EOF_CONFIG
expect_validation_failure \
  "$legacy_updater_secret_fixture" \
  .legacy-updater-secret.env \
  "GITHUB_RELEASE_UPDATER_REPO_URL must not include query strings or fragments: ${legacy_updater_secret_url}"

write_base_config "$runtime_url_pass_fixture/.runtime-url-pass.env"
cat >> "$runtime_url_pass_fixture/.runtime-url-pass.env" <<EOF_CONFIG
PLUGIN_RUNTIME_UPDATE_PROVIDER=generic-json
PLUGIN_RUNTIME_UPDATE_SOURCE_URL=${runtime_pass_url}
EOF_CONFIG
WP_PLUGIN_BASE_ROOT="$runtime_url_pass_fixture" bash "$VALIDATE_CONFIG" --scope project .runtime-url-pass.env >/dev/null

echo "Config runtime-pack contract tests passed."
