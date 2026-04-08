#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

CONFIG_OVERRIDE="${1:-}"

strict=false
if [ "$CONFIG_OVERRIDE" = "--strict" ] || [ "${WP_PLUGIN_BASE_STRICT_LINTERS:-false}" = "true" ]; then
  strict=true
  CONFIG_OVERRIDE=''
fi

if [ -n "$CONFIG_OVERRIDE" ] || [ -f "$SCRIPT_DIR/../../.wp-plugin-base.env" ]; then
  wp_plugin_base_load_config "$CONFIG_OVERRIDE"
else
  ROOT_DIR="${WP_PLUGIN_BASE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  if [ "$strict" = true ]; then
    echo "gitleaks is required for secret scanning." >&2
    exit 1
  fi

  echo "gitleaks not installed; skipping secret scanning."
  exit 0
fi

gitleaks dir "$ROOT_DIR" --no-banner --redact --exit-code 1

echo "Secret scan passed."
