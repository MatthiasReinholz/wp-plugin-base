#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

CURRENT_VERSION="${1:-}"
TARGET_REPOSITORY="${2:-WordPress/plugin-check}"
OUTPUT_PATH="${3:-${GITHUB_OUTPUT:-}}"

if [ -z "$CURRENT_VERSION" ]; then
  echo "Usage: $0 <current-version> [owner/repo] [output-path]" >&2
  exit 1
fi

wp_plugin_base_require_commands "plugin-check version resolution" jq curl

if [[ ! "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Current plugin-check version must use x.y.z format: $CURRENT_VERSION" >&2
  exit 1
fi

major="${CURRENT_VERSION%%.*}"
releases_json=''

if [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON:-}" ]; then
  if [ ! -f "$WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON" ]; then
    echo "Release JSON fixture not found: $WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON" >&2
    exit 1
  fi
  releases_json="$(cat "$WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON")"
else
  api_url="https://api.github.com/repos/${TARGET_REPOSITORY}/releases?per_page=100"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    releases_json="$(
      curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$api_url"
    )"
  else
    releases_json="$(
      curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$api_url"
    )"
  fi
fi

latest="$(
  printf '%s\n' "$releases_json" | jq -r --arg major "$major" '
    map(
      select(
        .draft == false and
        .prerelease == false and
        (.tag_name | test("^" + $major + "\\.[0-9]+\\.[0-9]+$"))
      )
    )
    | map(.tag_name)
    | sort_by(split(".") | map(tonumber))
    | last // empty
  '
)"

if [ -n "$OUTPUT_PATH" ]; then
  if [ -z "$latest" ] || [ "$latest" = "$CURRENT_VERSION" ]; then
    {
      echo "update_needed=false"
      echo "version="
    } >> "$OUTPUT_PATH"
    exit 0
  fi

  {
    echo "update_needed=true"
    echo "version=$latest"
  } >> "$OUTPUT_PATH"
  exit 0
fi

if [ -z "$latest" ] || [ "$latest" = "$CURRENT_VERSION" ]; then
  echo "update_needed=false"
  echo "version="
  exit 0
fi

echo "update_needed=true"
echo "version=$latest"
