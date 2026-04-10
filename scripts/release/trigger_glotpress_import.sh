#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "GlotPress import trigger" curl

VERSION="${1:-}"
CONFIG_OVERRIDE="${2:-}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z [config-path]" >&2
  exit 1
fi

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

if ! wp_plugin_base_is_true "${GLOTPRESS_TRIGGER_ENABLED:-false}"; then
  echo "GlotPress trigger disabled; skipping."
  exit 0
fi

if [ -z "${GLOTPRESS_URL:-}" ] || [ -z "${GLOTPRESS_PROJECT_SLUG:-}" ]; then
  echo "GlotPress trigger requires GLOTPRESS_URL and GLOTPRESS_PROJECT_SLUG." >&2
  exit 1
fi

glotpress_scheme="${GLOTPRESS_URL%%://*}"
glotpress_remainder="${GLOTPRESS_URL#*://}"
glotpress_host="${glotpress_remainder%%/*}"
if [ "$glotpress_scheme" != "https" ] || [[ ! "$glotpress_host" =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; then
  echo "GLOTPRESS_URL must be an https URL." >&2
  exit 1
fi

if [ -z "${GLOTPRESS_TOKEN:-}" ]; then
  echo "GLOTPRESS_TOKEN is required when GLOTPRESS_TRIGGER_ENABLED=true." >&2
  if wp_plugin_base_is_true "${GLOTPRESS_FAIL_ON_ERROR:-false}"; then
    exit 1
  fi
  echo "WARNING: Continuing without blocking release because GLOTPRESS_FAIL_ON_ERROR=false." >&2
  exit 0
fi

endpoint="${GLOTPRESS_URL%/}/api/translations/${GLOTPRESS_PROJECT_SLUG}/import-originals"
if curl -fsSL --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2 \
  -X POST \
  -H "Authorization: Bearer ${GLOTPRESS_TOKEN}" \
  -d "version=${VERSION}" \
  "$endpoint" >/dev/null; then
  echo "Triggered GlotPress import for ${GLOTPRESS_PROJECT_SLUG} version ${VERSION}."
  exit 0
fi

echo "Failed to trigger GlotPress import at ${endpoint}." >&2
if wp_plugin_base_is_true "${GLOTPRESS_FAIL_ON_ERROR:-false}"; then
  exit 1
fi
echo "WARNING: Continuing without blocking release because GLOTPRESS_FAIL_ON_ERROR=false." >&2
