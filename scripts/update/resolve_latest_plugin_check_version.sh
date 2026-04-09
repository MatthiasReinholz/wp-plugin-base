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

allowed_authors="${WP_PLUGIN_BASE_PLUGIN_CHECK_ALLOWED_RELEASE_AUTHORS:-}"
minimum_release_age_days="${WP_PLUGIN_BASE_PLUGIN_CHECK_MIN_RELEASE_AGE_DAYS:-0}"
major="${CURRENT_VERSION%%.*}"
releases_json=''

if [[ ! "$minimum_release_age_days" =~ ^[0-9]+$ ]]; then
  echo "WP_PLUGIN_BASE_PLUGIN_CHECK_MIN_RELEASE_AGE_DAYS must be a non-negative integer: $minimum_release_age_days" >&2
  exit 1
fi

current_epoch="${WP_PLUGIN_BASE_PLUGIN_CHECK_NOW_EPOCH:-$(date -u +%s)}"
if [[ ! "$current_epoch" =~ ^[0-9]+$ ]]; then
  echo "WP_PLUGIN_BASE_PLUGIN_CHECK_NOW_EPOCH must be a Unix epoch timestamp: $current_epoch" >&2
  exit 1
fi

if [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON:-}" ]; then
  if [ ! -f "$WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON" ]; then
    echo "Release JSON fixture not found: $WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON" >&2
    exit 1
  fi
  releases_json="$(cat "$WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON")"
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
      wp_plugin_base_run_with_retry 3 2 "Fetch plugin-check releases page ${page}" fetch_releases_page "$page"
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

latest="$(
  printf '%s\n' "$releases_json" | jq -r \
    --arg major "$major" \
    --arg allowed_authors "$allowed_authors" \
    --argjson minimum_release_age_days "$minimum_release_age_days" \
    --argjson current_epoch "$current_epoch" '
    map(
      select(
        .draft == false and
        .prerelease == false and
        (
          $allowed_authors == "" or
          ((.author.login // "") as $author | ($allowed_authors | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | index($author)) != null)
        ) and
        (
          $minimum_release_age_days == 0 or
          (
            (.published_at // "") != "" and
            (($current_epoch - (.published_at | fromdateiso8601)) >= ($minimum_release_age_days * 86400))
          )
        ) and
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
