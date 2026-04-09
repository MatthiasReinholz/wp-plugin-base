#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "foundation release provenance verification" curl jq

REPOSITORY="${1:-}"
VERSION="${2:-}"
OUTPUT_PATH="${3:-${GITHUB_OUTPUT:-}}"

if [ -z "$REPOSITORY" ] || [ -z "$VERSION" ]; then
  echo "Usage: $0 repository version [output-path]" >&2
  exit 1
fi

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  echo "GH_TOKEN or GITHUB_TOKEN is required." >&2
  exit 1
fi

allowed_authors="${FOUNDATION_ALLOWED_RELEASE_AUTHORS:-github-actions[bot]}"
verify_sigstore_script="${WP_PLUGIN_BASE_VERIFY_SIGSTORE_SCRIPT:-$SCRIPT_DIR/../release/verify_sigstore_bundle.sh}"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORK_DIR"
}

trap cleanup EXIT

api() {
  local path="$1"
  local fixture_path=""

  case "$path" in
    /repos/*/releases/tags/*)
      fixture_path="${WP_PLUGIN_BASE_FOUNDATION_RELEASE_JSON:-}"
      ;;
    /repos/*/git/ref/tags/*)
      fixture_path="${WP_PLUGIN_BASE_FOUNDATION_TAG_REF_JSON:-}"
      ;;
    /repos/*/git/tags/*)
      fixture_path="${WP_PLUGIN_BASE_FOUNDATION_TAG_OBJECT_JSON:-}"
      ;;
    /repos/*/compare/*)
      fixture_path="${WP_PLUGIN_BASE_FOUNDATION_COMPARE_JSON:-}"
      ;;
    /repos/*/commits/*/pulls)
      fixture_path="${WP_PLUGIN_BASE_FOUNDATION_PULLS_JSON:-}"
      ;;
  esac

  if [ -n "$fixture_path" ]; then
    if [ ! -f "$fixture_path" ]; then
      echo "Foundation API fixture not found: $fixture_path" >&2
      exit 1
    fi
    cat "$fixture_path"
    return
  fi

  wp_plugin_base_run_with_retry 3 2 "Foundation API request: ${path}" \
    curl -fsSL \
    --connect-timeout 10 \
    --max-time 60 \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com${path}"
}

download_release_asset() {
  local release_json="$1"
  local asset_name="$2"
  local destination_path="$3"
  local asset_url
  local override_path=""

  case "$asset_name" in
    dist-foundation-release.json)
      override_path="${WP_PLUGIN_BASE_FOUNDATION_METADATA_ASSET:-}"
      ;;
    dist-foundation-release.json.sigstore.json)
      override_path="${WP_PLUGIN_BASE_FOUNDATION_SIGSTORE_ASSET:-}"
      ;;
  esac

  if [ -n "$override_path" ]; then
    if [ ! -f "$override_path" ]; then
      echo "Foundation asset fixture not found: $override_path" >&2
      exit 1
    fi
    cp "$override_path" "$destination_path"
    return
  fi

  asset_url="$(
    printf '%s' "$release_json" | jq -r --arg name "$asset_name" '
      .assets[]
      | select(.name == $name)
      | .url
    ' | head -n 1
  )"

  if [ -z "$asset_url" ] || [ "$asset_url" = "null" ]; then
    echo "Foundation release ${VERSION} is missing required asset: ${asset_name}" >&2
    exit 1
  fi

  wp_plugin_base_run_with_retry 3 2 "Download foundation asset ${asset_name}" \
    curl -fsSL \
    --connect-timeout 10 \
    --max-time 60 \
    -H "Accept: application/octet-stream" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$asset_url" \
    -o "$destination_path"
}

release_json="$(api "/repos/${REPOSITORY}/releases/tags/${VERSION}")"

if [ "$(printf '%s' "$release_json" | jq -r '.draft')" != "false" ]; then
  echo "Foundation release ${VERSION} is still a draft." >&2
  exit 1
fi

if [ "$(printf '%s' "$release_json" | jq -r '.prerelease')" != "false" ]; then
  echo "Foundation release ${VERSION} is a prerelease." >&2
  exit 1
fi

release_author="$(printf '%s' "$release_json" | jq -r '.author.login // empty')"
author_allowed=false
while IFS= read -r author; do
  if [ "$author" = "$release_author" ]; then
    author_allowed=true
    break
  fi
done < <(printf '%s\n' "$allowed_authors" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [ "$author_allowed" != true ]; then
  echo "Foundation release ${VERSION} was authored by ${release_author}, which is not in the allowlist." >&2
  exit 1
fi

tag_ref_json="$(api "/repos/${REPOSITORY}/git/ref/tags/${VERSION}")"
tag_object_type="$(printf '%s' "$tag_ref_json" | jq -r '.object.type')"
tag_object_sha="$(printf '%s' "$tag_ref_json" | jq -r '.object.sha')"

if [ "$tag_object_type" = "tag" ]; then
  tag_object_json="$(api "/repos/${REPOSITORY}/git/tags/${tag_object_sha}")"
  commit_sha="$(printf '%s' "$tag_object_json" | jq -r '.object.sha')"
else
  commit_sha="$tag_object_sha"
fi

compare_json="$(
  api "/repos/${REPOSITORY}/compare/${commit_sha}...main"
)"
compare_status="$(printf '%s' "$compare_json" | jq -r '.status')"

if [ "$compare_status" != "behind" ] && [ "$compare_status" != "identical" ]; then
  echo "Foundation release ${VERSION} does not point to a commit on main." >&2
  exit 1
fi

metadata_path="$WORK_DIR/dist-foundation-release.json"
sigstore_path="$WORK_DIR/dist-foundation-release.json.sigstore.json"

download_release_asset "$release_json" "dist-foundation-release.json" "$metadata_path"
download_release_asset "$release_json" "dist-foundation-release.json.sigstore.json" "$sigstore_path"

bash "$verify_sigstore_script" \
  "$REPOSITORY" \
  "$metadata_path" \
  "$sigstore_path" \
  foundation

metadata_repository="$(jq -r '.repository // empty' "$metadata_path")"
metadata_version="$(jq -r '.version // empty' "$metadata_path")"
metadata_commit="$(jq -r '.commit // empty' "$metadata_path")"

if [ "$metadata_repository" != "$REPOSITORY" ]; then
  echo "Foundation release metadata repository ${metadata_repository} does not match ${REPOSITORY}." >&2
  exit 1
fi

if [ "$metadata_version" != "$VERSION" ]; then
  echo "Foundation release metadata version ${metadata_version} does not match ${VERSION}." >&2
  exit 1
fi

if [ "$metadata_commit" != "$commit_sha" ]; then
  echo "Foundation release metadata commit ${metadata_commit} does not match ${commit_sha}." >&2
  exit 1
fi

pulls_json="$(api "/repos/${REPOSITORY}/commits/${commit_sha}/pulls")"

matching_count="$(printf '%s' "$pulls_json" | jq -r --arg sha "$commit_sha" '
  map(
    select(
      .merged_at != null and
      .base.ref == "main" and
      (.head.ref | test("^(release|hotfix)/v[0-9]+\\.[0-9]+\\.[0-9]+$")) and
      .merge_commit_sha == $sha
    )
  ) | length
')"

if [ "$matching_count" -eq 0 ]; then
  echo "Foundation release ${VERSION} was not produced by a merged release/hotfix PR on main." >&2
  exit 1
fi

if [ -n "$OUTPUT_PATH" ]; then
  {
    echo "version=$VERSION"
    echo "commit_sha=$commit_sha"
  } >> "$OUTPUT_PATH"
fi

echo "Verified provenance for ${REPOSITORY} ${VERSION} (${commit_sha})"
