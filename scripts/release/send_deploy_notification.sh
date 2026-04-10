#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "deployment notification" curl jq

VERSION="${1:-}"
CONFIG_OVERRIDE="${2:-}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z [config-path]" >&2
  exit 1
fi

wp_plugin_base_load_config "$CONFIG_OVERRIDE"
wp_plugin_base_require_vars PLUGIN_NAME PLUGIN_SLUG

if ! wp_plugin_base_is_true "${DEPLOY_NOTIFICATION_ENABLED:-false}"; then
  echo "Deploy notification disabled; skipping."
  exit 0
fi

if [ -z "${DEPLOY_NOTIFICATION_WEBHOOK_URL:-}" ]; then
  echo "WARNING: DEPLOY_NOTIFICATION_WEBHOOK_URL is missing; skipping deploy notification." >&2
  exit 0
fi

webhook_scheme="${DEPLOY_NOTIFICATION_WEBHOOK_URL%%://*}"
webhook_remainder="${DEPLOY_NOTIFICATION_WEBHOOK_URL#*://}"
webhook_host="${webhook_remainder%%/*}"
if [ "$webhook_scheme" != "https" ] || [[ ! "$webhook_host" =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; then
  echo "WARNING: DEPLOY_NOTIFICATION_WEBHOOK_URL must be an https URL; skipping notification." >&2
  exit 0
fi

repository="${GITHUB_REPOSITORY:-unknown/unknown}"
release_url="https://github.com/${repository}/releases/tag/${VERSION}"
timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

payload="$(
  jq -n \
    --arg event "release_published" \
    --arg plugin_name "$PLUGIN_NAME" \
    --arg plugin_slug "$PLUGIN_SLUG" \
    --arg version "$VERSION" \
    --arg repository "$repository" \
    --arg release_url "$release_url" \
    --arg timestamp "$timestamp" \
    '{
      event: $event,
      plugin_name: $plugin_name,
      plugin_slug: $plugin_slug,
      version: $version,
      repository: $repository,
      release_url: $release_url,
      timestamp: $timestamp
    }'
)"

if curl -fsSL --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 2 \
  -X POST \
  -H "Content-Type: application/json" \
  -d "$payload" \
  "$DEPLOY_NOTIFICATION_WEBHOOK_URL" >/dev/null; then
  echo "Deployment notification sent for ${PLUGIN_SLUG} ${VERSION}."
  exit 0
fi

echo "WARNING: Failed to send deploy notification for ${PLUGIN_SLUG} ${VERSION}." >&2
