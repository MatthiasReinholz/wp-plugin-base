#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "GitLab release publication" curl jq basename mktemp

REPAIR_MODE=false
if [ "${1:-}" = "--repair" ]; then
  REPAIR_MODE=true
  shift
fi

VERSION="${1:-}"
RELEASE_NAME="${2:-}"
BODY_PATH="${3:-}"
shift 3 2>/dev/null || true
ASSET_PATHS=("$@")

if [ -z "$VERSION" ] || [ -z "$RELEASE_NAME" ] || [ -z "$BODY_PATH" ] || [ "${#ASSET_PATHS[@]}" -eq 0 ]; then
  echo "Usage: $0 [--repair] <version> <release-name> <release-body-path> <asset-path>..." >&2
  exit 1
fi

if [ ! -f "$BODY_PATH" ]; then
  echo "Release body file not found: $BODY_PATH" >&2
  exit 1
fi

for asset_path in "${ASSET_PATHS[@]}"; do
  if [ ! -f "$asset_path" ]; then
    echo "Release asset not found: $asset_path" >&2
    exit 1
  fi
done

GITLAB_API_BASE="${CI_API_V4_URL:-${GITLAB_API_BASE:-${AUTOMATION_API_BASE:-https://gitlab.com/api/v4}}}"
GITLAB_PROJECT_PATH="${CI_PROJECT_PATH:-${GITLAB_PROJECT_PATH:-}}"
if [ -z "$GITLAB_PROJECT_PATH" ]; then
  echo "CI_PROJECT_PATH or GITLAB_PROJECT_PATH is required." >&2
  exit 1
fi

gitlab_token="${GITLAB_TOKEN:-${CI_JOB_TOKEN:-}}"
if [ -z "$gitlab_token" ]; then
  echo "GITLAB_TOKEN or CI_JOB_TOKEN is required." >&2
  exit 1
fi

gitlab_auth_header_name="PRIVATE-TOKEN"
if [ -z "${GITLAB_TOKEN:-}" ] && [ -n "${CI_JOB_TOKEN:-}" ]; then
  gitlab_auth_header_name="JOB-TOKEN"
fi

gitlab_project_id="$(wp_plugin_base_provider_gitlab_project_id "$GITLAB_PROJECT_PATH")"
gitlab_web_base="$(wp_plugin_base_provider_gitlab_web_base "$GITLAB_API_BASE")"
encoded_version="$(jq -rn --arg value "$VERSION" '$value | @uri')"
body_content="$(cat "$BODY_PATH")"
tmp_response="$(mktemp)"

cleanup() {
  rm -f "$tmp_response"
}
trap cleanup EXIT

gitlab_api_json() {
  local method="$1"
  local url="$2"
  shift 2

  curl -fsSL \
    --request "$method" \
    --connect-timeout 10 \
    --max-time 120 \
    --header "${gitlab_auth_header_name}: ${gitlab_token}" \
    "$@" \
    "$url"
}

gitlab_api_status() {
  local method="$1"
  local url="$2"
  shift 2

  curl -sS \
    --request "$method" \
    --connect-timeout 10 \
    --max-time 120 \
    --header "${gitlab_auth_header_name}: ${gitlab_token}" \
    "$@" \
    --output "$tmp_response" \
    --write-out '%{http_code}' \
    "$url"
}

release_url="${GITLAB_API_BASE}/projects/${gitlab_project_id}/releases/${encoded_version}"
release_status="$(gitlab_api_status GET "$release_url")"

case "$release_status" in
  200)
    if [ "$REPAIR_MODE" != true ]; then
      echo "Release ${VERSION} already exists. Re-run with --repair to update an existing release." >&2
      exit 1
    fi
    release_method="PUT"
    ;;
  404)
    release_method="POST"
    ;;
  *)
    cat "$tmp_response" >&2 || true
    echo "GitLab release lookup failed with HTTP ${release_status}." >&2
    exit 1
    ;;
esac

release_payload="$(
  jq -n \
    --arg name "$RELEASE_NAME" \
    --arg tag_name "$VERSION" \
    --arg description "$body_content" \
    '{
      name: $name,
      tag_name: $tag_name,
      description: $description
    }'
)"

case "$release_method" in
  POST)
    gitlab_api_json \
      POST \
      "${GITLAB_API_BASE}/projects/${gitlab_project_id}/releases" \
      --header 'Content-Type: application/json' \
      --data "$release_payload" >/dev/null
    ;;
  PUT)
    gitlab_api_json \
      PUT \
      "$release_url" \
      --header 'Content-Type: application/json' \
      --data "$release_payload" >/dev/null
    ;;
esac

links_url="${GITLAB_API_BASE}/projects/${gitlab_project_id}/releases/${encoded_version}/assets/links"
existing_links_json="$(gitlab_api_json GET "$links_url")"

for asset_path in "${ASSET_PATHS[@]}"; do
  asset_name="$(basename "$asset_path")"
  upload_json="$(
    gitlab_api_json \
      POST \
      "${GITLAB_API_BASE}/projects/${gitlab_project_id}/uploads" \
      --form "file=@${asset_path}"
  )"
  upload_path="$(printf '%s' "$upload_json" | jq -r '.full_path // .url // empty')"
  if [ -z "$upload_path" ]; then
    echo "Upload response for ${asset_name} did not include a URL." >&2
    exit 1
  fi

  asset_url="$upload_path"
  case "$asset_url" in
    /*)
      asset_url="${gitlab_web_base}${asset_url}"
      ;;
  esac

  direct_asset_path="/packages/${VERSION}/${asset_name}"
  link_type="other"
  case "$asset_name" in
    *.zip)
      link_type="package"
      ;;
  esac

  existing_link_id="$(
    printf '%s' "$existing_links_json" | jq -r --arg name "$asset_name" '
      map(select(.name == $name))
      | .[0].id // empty
    '
  )"

  if [ -n "$existing_link_id" ]; then
    gitlab_api_json \
      PUT \
      "${links_url}/${existing_link_id}" \
      --data-urlencode "name=${asset_name}" \
      --data-urlencode "url=${asset_url}" \
      --data-urlencode "direct_asset_path=${direct_asset_path}" \
      --data-urlencode "link_type=${link_type}" >/dev/null
  else
    gitlab_api_json \
      POST \
      "$links_url" \
      --data-urlencode "name=${asset_name}" \
      --data-urlencode "url=${asset_url}" \
      --data-urlencode "direct_asset_path=${direct_asset_path}" \
      --data-urlencode "link_type=${link_type}" >/dev/null
  fi
done

echo "Published GitLab release ${VERSION} for ${GITLAB_PROJECT_PATH}."
