#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "GitLab release publication" curl jq basename mktemp cmp

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
work_dir="$(mktemp -d)"
tmp_response="$work_dir/response.json"
auth_header="$work_dir/auth-header"
(
  umask 077
  printf '%s: %s\n' "$gitlab_auth_header_name" "$gitlab_token" > "$auth_header"
)
unset gitlab_token

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

gitlab_api_json() {
  local method="$1"
  local url="$2"
  shift 2

  curl -fsS \
    --request "$method" \
    --connect-timeout 10 \
    --max-time 120 \
    --header "@$auth_header" \
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
    --header "@$auth_header" \
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

# GitLab chooses its latest release by publication time. Do not create an
# older stable version after a newer version has already been published.
if [ "$release_method" = "POST" ]; then
  page=1
  while :; do
    releases="$(gitlab_api_json GET "${GITLAB_API_BASE}/projects/${gitlab_project_id}/releases?per_page=100&page=$page")"
    newer_versions="$(printf '%s' "$releases" | jq -r --arg candidate "${VERSION#v}" '
      ($candidate | split(".") | map(tonumber)) as $candidate_version
      | .[].tag_name | select(test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$"))
      | select((ltrimstr("v") | split(".") | map(tonumber)) > $candidate_version)
    ')"
    if [ -n "$newer_versions" ]; then
      echo "Refusing to publish historical version $VERSION as GitLab latest; newer release(s): $newer_versions." >&2
      exit 1
    fi
    [ "$(printf '%s' "$releases" | jq 'length')" -eq 100 ] || break
    page=$((page + 1))
  done
fi

links_url="${GITLAB_API_BASE}/projects/${gitlab_project_id}/releases/${encoded_version}/assets/links"
existing_links_json='[]'
if [ "$release_method" = "PUT" ]; then
  existing_links_json="$(gitlab_api_json GET "$links_url")"
fi
new_links_json='[]'

for asset_path in "${ASSET_PATHS[@]}"; do
  asset_name="$(basename "$asset_path")"
  # Keep existing payload bytes immutable. Only same-origin upload URLs are
  # accepted when credentials are sent; a remote link cannot receive the token.
  if [[ "$asset_name" = *.zip ]]; then
    existing_asset_url="$(printf '%s' "$existing_links_json" | jq -r --arg name "$asset_name" 'map(select(.name == $name)) | .[0].url // empty')"
    if [ -n "$existing_asset_url" ]; then
      existing_asset_url="$(wp_plugin_base_provider_gitlab_asset_api_url "$GITLAB_API_BASE" "$GITLAB_PROJECT_PATH" "$existing_asset_url")"
      curl --fail --silent --show-error --connect-timeout 10 --max-time 120 \
        --header "@$auth_header" "$existing_asset_url" --output "$work_dir/existing-payload"
      if ! cmp -s "$asset_path" "$work_dir/existing-payload"; then
        echo "Published payload $asset_name differs; publish a new version instead of replacing it." >&2
        exit 1
      fi
    fi
  fi
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

  if [ "$release_method" = "POST" ]; then
    new_links_json="$(printf '%s' "$new_links_json" | jq \
      --arg name "$asset_name" --arg url "$asset_url" \
      --arg path "$direct_asset_path" --arg type "$link_type" \
      '. + [{name: $name, url: $url, direct_asset_path: $path, link_type: $type}]')"
    continue
  fi

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

release_payload="$(jq -n --arg name "$RELEASE_NAME" --arg tag_name "$VERSION" \
  --arg description "$body_content" --argjson links "$new_links_json" \
  '{name: $name, tag_name: $tag_name, description: $description} +
    (if ($links | length) > 0 then {assets: {links: $links}} else {} end)')"
if [ "$release_method" = "POST" ]; then
  release_url="${GITLAB_API_BASE}/projects/${gitlab_project_id}/releases"
fi
gitlab_api_json "$release_method" "$release_url" \
  --header 'Content-Type: application/json' --data "$release_payload" >/dev/null

echo "Published GitLab release ${VERSION} for ${GITLAB_PROJECT_PATH}."
