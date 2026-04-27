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

wp_plugin_base_require_commands "WordPress security pack" docker php python3
wp_plugin_base_load_config "$CONFIG_OVERRIDE"

if ! wp_plugin_base_is_true "$WORDPRESS_SECURITY_PACK_ENABLED"; then
  echo "WordPress security pack is disabled; skipping."
  exit 0
fi

TOOLS_DIR="$ROOT_DIR/.wp-plugin-base-security-pack"
COMPOSER_WORK_DIR="$(mktemp -d)"
COMPOSER_CACHE_DIR="$(mktemp -d)"
NPM_CACHE_DIR="$(mktemp -d)"
SEMGREP_TOOLS_DIR=''
SEMGREP_SARIF_PATH="$ROOT_DIR/dist/semgrep-security.sarif"

audit_npm_lockfile() {
  local audit_dir="$1"
  local description="$2"
  local audit_level="$3"
  shift 3

  if ! command -v npm >/dev/null 2>&1; then
    echo "npm is required to audit ${description} when the security pack is enabled." >&2
    exit 1
  fi

  npm_audit_command() {
    (
      cd "$audit_dir"
      NPM_CONFIG_CACHE="$NPM_CACHE_DIR" npm audit --package-lock-only --audit-level="$audit_level" "$@"
    )
  }

  wp_plugin_base_run_with_retry 3 5 "${description} npm audit" npm_audit_command "$@"
}

cleanup() {
  rm -rf "$COMPOSER_WORK_DIR" "$COMPOSER_CACHE_DIR" "$NPM_CACHE_DIR"
  if [ -n "$SEMGREP_TOOLS_DIR" ]; then
    rm -rf "$SEMGREP_TOOLS_DIR"
  fi
}

trap cleanup EXIT

for required_file in \
  "$ROOT_DIR/.phpcs-security.xml.dist" \
  "$TOOLS_DIR/composer.lock" \
  "$TOOLS_DIR/composer.json"; do
  if [ ! -f "$required_file" ]; then
    echo "Missing managed security pack file: $required_file" >&2
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

wp_plugin_base_run_with_retry 3 2 "Security pack Composer install" composer_install_command

security_pack_composer_audit_command() {
  docker run --rm \
    -u "$(id -u):$(id -g)" \
    -e COMPOSER_CACHE_DIR=/tmp/composer-cache \
    -v "$COMPOSER_CACHE_DIR":/tmp/composer-cache \
    -v "$COMPOSER_WORK_DIR":/workspace \
    -w /workspace \
    "$WP_PLUGIN_BASE_COMPOSER_IMAGE" \
    audit --locked --no-interaction
}

wp_plugin_base_run_with_retry 3 5 "Security pack Composer audit" security_pack_composer_audit_command

php "$COMPOSER_WORK_DIR/vendor/bin/phpcs" --standard="$ROOT_DIR/.phpcs-security.xml.dist"
if wp_plugin_base_is_true "${WP_PLUGIN_BASE_SECURITY_PACK_SKIP_SEMGREP:-false}"; then
  echo "Semgrep pass is delegated to a separate step; skipping Semgrep execution in security pack."
else
  SEMGREP_TOOLS_DIR="$(mktemp -d)"
  bash "$SCRIPT_DIR/install_lint_tools.sh" "$SEMGREP_TOOLS_DIR" semgrep >/dev/null
  export PATH="$SEMGREP_TOOLS_DIR:$PATH"
  bash "$SCRIPT_DIR/run_semgrep_security.sh" "$CONFIG_OVERRIDE" "$SEMGREP_SARIF_PATH"
  if [ ! -s "$SEMGREP_SARIF_PATH" ]; then
    echo "Security pack did not produce the expected Semgrep SARIF report: $SEMGREP_SARIF_PATH" >&2
    exit 1
  fi
fi
bash "$SCRIPT_DIR/scan_wordpress_authorization_patterns.sh" "$CONFIG_OVERRIDE"

if [ -f "$ROOT_DIR/composer.lock" ] && [ -f "$ROOT_DIR/composer.json" ]; then
  root_composer_audit_command() {
    docker run --rm \
      -u "$(id -u):$(id -g)" \
      -e COMPOSER_CACHE_DIR=/tmp/composer-cache \
      -v "$COMPOSER_CACHE_DIR":/tmp/composer-cache \
      -v "$ROOT_DIR":/workspace \
      -w /workspace \
      "$WP_PLUGIN_BASE_COMPOSER_IMAGE" \
      audit --locked --no-interaction --no-dev
  }

  wp_plugin_base_run_with_retry 3 5 "Root Composer dependency audit" root_composer_audit_command
else
  echo "No root composer.lock found; skipping Composer dependency audit."
fi

if [ -f "$ROOT_DIR/package-lock.json" ] && [ -f "$ROOT_DIR/package.json" ]; then
  audit_npm_lockfile "$ROOT_DIR" "package-lock.json" high --omit=dev
else
  echo "No root package-lock.json found; skipping npm dependency audit."
fi

if wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}" && [ -f "$ROOT_DIR/.wp-plugin-base-admin-ui/package-lock.json" ] && [ -f "$ROOT_DIR/.wp-plugin-base-admin-ui/package.json" ]; then
  audit_npm_lockfile "$ROOT_DIR/.wp-plugin-base-admin-ui" ".wp-plugin-base-admin-ui/package-lock.json" "$ADMIN_UI_NPM_AUDIT_LEVEL"
elif wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}" && [ "${RELEASE_READINESS_MODE:-standard}" = "security-sensitive" ]; then
  echo "RELEASE_READINESS_MODE=security-sensitive requires .wp-plugin-base-admin-ui/package.json and package-lock.json so the admin UI toolchain can be audited." >&2
  exit 1
else
  echo "No .wp-plugin-base-admin-ui/package-lock.json found; skipping admin UI npm dependency audit."
fi

echo "Validated WordPress security pack."
