#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

CURRENT_VERSION="${1:-}"
TARGET_REFERENCE="${2:-}"
OUTPUT_PATH="${3:-${GITHUB_OUTPUT:-}}"
SOURCE_PROVIDER="${4:-${FOUNDATION_RELEASE_SOURCE_PROVIDER:-github-release}}"
SOURCE_API_BASE="${5:-${FOUNDATION_RELEASE_SOURCE_API_BASE:-}}"

if [ -z "$CURRENT_VERSION" ] || [ -z "$TARGET_REFERENCE" ]; then
  echo "Usage: $0 <current-version> <reference> [output-path] [provider] [api-base]" >&2
  exit 1
fi

wp_plugin_base_require_commands "foundation version resolution" jq curl

if [[ ! "$CURRENT_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Current foundation version must use vX.Y.Z format: $CURRENT_VERSION" >&2
  exit 1
fi

if [ -z "$SOURCE_API_BASE" ]; then
  SOURCE_API_BASE="$(wp_plugin_base_provider_default_api_base "$SOURCE_PROVIDER")"
fi

major="${CURRENT_VERSION%%.*}"
releases_json=''

github_api_get() {
  local url="$1"

  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL \
      --connect-timeout 10 \
      --max-time 60 \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url"
    return
  fi

  curl -fsSL \
    --connect-timeout 10 \
    --max-time 60 \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$url"
}

gitlab_api_get() {
  local url="$1"
  local token="${GITLAB_TOKEN:-${CI_JOB_TOKEN:-}}"
  local header_name="PRIVATE-TOKEN"

  if [ -z "${GITLAB_TOKEN:-}" ] && [ -n "${CI_JOB_TOKEN:-}" ]; then
    header_name="JOB-TOKEN"
  fi

  if [ -n "$token" ]; then
    curl -fsSL \
      --connect-timeout 10 \
      --max-time 60 \
      --header "${header_name}: ${token}" \
      "$url"
    return
  fi

  curl -fsSL \
    --connect-timeout 10 \
    --max-time 60 \
    "$url"
}

fetch_releases_page() {
  local page="$1"
  local api_url=""

  case "$SOURCE_PROVIDER" in
    github|github-release)
      api_url="${SOURCE_API_BASE}/repos/${TARGET_REFERENCE}/releases?per_page=100&page=${page}"
      wp_plugin_base_run_with_retry 3 2 "Fetch foundation releases page ${page}" github_api_get "$api_url"
      ;;
    gitlab|gitlab-release)
      api_url="${SOURCE_API_BASE}/projects/$(wp_plugin_base_provider_gitlab_project_id "$TARGET_REFERENCE")/releases?per_page=100&page=${page}"
      wp_plugin_base_run_with_retry 3 2 "Fetch foundation releases page ${page}" gitlab_api_get "$api_url"
      ;;
    *)
      echo "Unsupported foundation release source provider: ${SOURCE_PROVIDER}" >&2
      exit 1
      ;;
  esac
}

if [ -n "${WP_PLUGIN_BASE_FOUNDATION_RELEASES_JSON:-}" ]; then
  if [ ! -f "$WP_PLUGIN_BASE_FOUNDATION_RELEASES_JSON" ]; then
    echo "Foundation release JSON fixture not found: $WP_PLUGIN_BASE_FOUNDATION_RELEASES_JSON" >&2
    exit 1
  fi
  releases_json="$(cat "$WP_PLUGIN_BASE_FOUNDATION_RELEASES_JSON")"
else
  page=1
  releases_json='[]'

  while :; do
    page_json="$(fetch_releases_page "$page")"

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

case "$SOURCE_PROVIDER" in
  github|github-release)
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
    ;;
  gitlab|gitlab-release)
    candidates="$(
      printf '%s\n' "$releases_json" | jq -r --arg major "$major" --arg current "$CURRENT_VERSION" '
        map(
          select(
            (.upcoming_release // false) == false and
            (.released_at // empty) != "" and
            (.tag_name | test("^" + $major + "\\.[0-9]+\\.[0-9]+$")) and
            ((.tag_name | split(".") | map(ltrimstr("v") | tonumber)) > ($current | split(".") | map(ltrimstr("v") | tonumber)))
          )
        )
        | map(.tag_name)
        | sort_by(split(".") | map(ltrimstr("v") | tonumber))
        | reverse[]
      '
    )"
    ;;
  *)
    echo "Unsupported foundation release source provider: ${SOURCE_PROVIDER}" >&2
    exit 1
    ;;
esac

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
