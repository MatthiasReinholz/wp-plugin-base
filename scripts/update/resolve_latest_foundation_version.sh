#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

CURRENT_VERSION="${1:-}"
TARGET_REPOSITORY="${2:-}"
OUTPUT_PATH="${3:-${GITHUB_OUTPUT:-}}"

if [ -z "$CURRENT_VERSION" ] || [ -z "$TARGET_REPOSITORY" ]; then
  echo "Usage: $0 <current-version> <owner/repo> [output-path]" >&2
  exit 1
fi

wp_plugin_base_require_commands "foundation version resolution" jq curl

if [[ ! "$CURRENT_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Current foundation version must use vX.Y.Z format: $CURRENT_VERSION" >&2
  exit 1
fi

major="${CURRENT_VERSION%%.*}"
releases_json=''

if [ -n "${WP_PLUGIN_BASE_FOUNDATION_RELEASES_JSON:-}" ]; then
  if [ ! -f "$WP_PLUGIN_BASE_FOUNDATION_RELEASES_JSON" ]; then
    echo "Foundation release JSON fixture not found: $WP_PLUGIN_BASE_FOUNDATION_RELEASES_JSON" >&2
    exit 1
  fi
  releases_json="$(cat "$WP_PLUGIN_BASE_FOUNDATION_RELEASES_JSON")"
else
  fetch_releases_page() {
    local page="$1"
    local api_url="https://api.github.com/repos/${TARGET_REPOSITORY}/releases?per_page=100&page=${page}"

    if [ -n "${GITHUB_TOKEN:-}" ]; then
      curl -fsSL \
        --connect-timeout 10 \
        --max-time 60 \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$api_url"
      return
    fi

    curl -fsSL \
      --connect-timeout 10 \
      --max-time 60 \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$api_url"
  }

  page=1
  releases_json='[]'

  while :; do
    page_json="$(
      wp_plugin_base_run_with_retry 3 2 "Fetch foundation releases page ${page}" fetch_releases_page "$page"
    )"

    releases_json="$(
      jq -s '.[0] + .[1]' \
        <(printf '%s\n' "$releases_json") \
        <(printf '%s\n' "$page_json")
    )"

    page_count="$(printf '%s\n' "$page_json" | jq 'length')"
    if [ "$page_count" -lt 100 ]; then
      break
    fi

    page=$((page + 1))
  done
fi

candidates="$(
  printf '%s\n' "$releases_json" | jq -r --arg major "$major" --arg current "$CURRENT_VERSION" '
    map(
      select(
        .draft == false and
        .prerelease == false and
        (.tag_name | test("^" + $major + "\\.[0-9]+\\.[0-9]+$")) and
        ((.tag_name | split(".") | map(ltrimstr("v") | tonumber)) > ($current | split(".") | map(ltrimstr("v") | tonumber)))
      )
    )
    | map(.tag_name)
    | sort_by(split(".") | map(ltrimstr("v") | tonumber))
    | reverse[]
  '
)"
latest="$(printf '%s\n' "$candidates" | head -n 1)"

if [ -n "$OUTPUT_PATH" ]; then
  if [ -z "$latest" ] || [ "$latest" = "$CURRENT_VERSION" ]; then
    {
      echo "update_needed=false"
      echo "version="
      echo "candidates="
    } >> "$OUTPUT_PATH"
    exit 0
  fi

  {
    echo "update_needed=true"
    echo "version=$latest"
    echo "candidates<<EOF"
    printf '%s\n' "$candidates"
    echo "EOF"
  } >> "$OUTPUT_PATH"
  exit 0
fi

if [ -z "$latest" ] || [ "$latest" = "$CURRENT_VERSION" ]; then
  echo "update_needed=false"
  echo "version="
  echo "candidates="
  exit 0
fi

echo "update_needed=true"
echo "version=$latest"
echo "candidates<<EOF"
printf '%s\n' "$candidates"
echo "EOF"
