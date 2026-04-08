#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

EXTENSION_SLUG="${1:-}"
TEST_SUITES="${2:-activation,security,validation,phpcompatibility,phpstan}"
QIT_CLI_VERSION='1.1.8'

if [ -z "$EXTENSION_SLUG" ]; then
  echo "Usage: $0 <extension-slug> [test-suites]" >&2
  exit 1
fi

wp_plugin_base_load_config "${WP_PLUGIN_BASE_CONFIG:-}"

if ! command -v composer >/dev/null 2>&1; then
  echo "Composer is required to run WooCommerce QIT." >&2
  exit 1
fi

if [ -z "${QIT_USER:-}" ] || [ -z "${QIT_APP_PASSWORD:-}" ]; then
  echo "QIT_USER and QIT_APP_PASSWORD must be set to run WooCommerce QIT." >&2
  exit 1
fi

COMPOSER_HOME_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$COMPOSER_HOME_DIR"
}
trap cleanup EXIT

export COMPOSER_HOME="$COMPOSER_HOME_DIR"
export PATH="$COMPOSER_HOME_DIR/vendor/bin:$PATH"

composer global require --no-interaction --no-progress "woocommerce/qit-cli:${QIT_CLI_VERSION}" >/dev/null

while IFS= read -r suite; do
  [ -n "$suite" ] || continue
  qit "run:${suite}" "$EXTENSION_SLUG"
done < <(printf '%s\n' "$TEST_SUITES" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d')
