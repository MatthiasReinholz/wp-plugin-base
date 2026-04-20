#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "foundation release provenance verification" curl jq

REFERENCE="${1:-}"
VERSION="${2:-}"
OUTPUT_PATH="${3:-${GITHUB_OUTPUT:-}}"
SOURCE_PROVIDER="${4:-${FOUNDATION_RELEASE_SOURCE_PROVIDER:-github-release}}"
SOURCE_API_BASE="${5:-${FOUNDATION_RELEASE_SOURCE_API_BASE:-}}"
SOURCE_SIGSTORE_ISSUER="${6:-${FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER:-}}"

if [ -z "$REFERENCE" ] || [ -z "$VERSION" ]; then
  echo "Usage: $0 <reference> <version> [output-path] [provider] [api-base]" >&2
  exit 1
fi

if [ -z "$SOURCE_API_BASE" ]; then
  SOURCE_API_BASE="$(wp_plugin_base_provider_default_api_base "$SOURCE_PROVIDER")"
fi

github_api_get() {
  local url="$1"
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

  if [ -z "$token" ]; then
    echo "GH_TOKEN or GITHUB_TOKEN is required." >&2
    exit 1
  fi

  wp_plugin_base_run_with_retry 3 2 "Foundation API request: ${url}" \
    curl -fsSL \
    --connect-timeout 10 \
    --max-time 60 \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${token}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$url"
}

github_asset_download() {
  local url="$1"
  local destination_path="$2"
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

  if [ -z "$token" ]; then
    echo "GH_TOKEN or GITHUB_TOKEN is required." >&2
    exit 1
  fi

  wp_plugin_base_run_with_retry 3 2 "Download foundation asset: ${url}" \
    curl -fsSL \
    --connect-timeout 10 \
    --max-time 60 \
    -H "Accept: application/octet-stream" \
    -H "Authorization: Bearer ${token}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$url" \
    -o "$destination_path"
}

gitlab_api_get() {
  local url="$1"
  local token="${GITLAB_TOKEN:-${CI_JOB_TOKEN:-}}"
  local header_name="PRIVATE-TOKEN"

  if [ -z "${GITLAB_TOKEN:-}" ] && [ -n "${CI_JOB_TOKEN:-}" ]; then
    header_name="JOB-TOKEN"
  fi

  if [ -z "$token" ]; then
    wp_plugin_base_run_with_retry 3 2 "Foundation API request: ${url}" \
      curl -fsSL \
      --connect-timeout 10 \
      --max-time 60 \
      "$url"
    return
  fi

  wp_plugin_base_run_with_retry 3 2 "Foundation API request: ${url}" \
    curl -fsSL \
    --connect-timeout 10 \
    --max-time 60 \
    --header "${header_name}: ${token}" \
    "$url"
}

gitlab_asset_download() {
  local url="$1"
  local destination_path="$2"
  local token="${GITLAB_TOKEN:-${CI_JOB_TOKEN:-}}"
  local header_name="PRIVATE-TOKEN"

  if [ -z "${GITLAB_TOKEN:-}" ] && [ -n "${CI_JOB_TOKEN:-}" ]; then
    header_name="JOB-TOKEN"
  fi

  if [ -z "$token" ]; then
    wp_plugin_base_run_with_retry 3 2 "Download foundation asset: ${url}" \
      curl -fsSL \
      --connect-timeout 10 \
      --max-time 60 \
      "$url" \
      -o "$destination_path"
    return
  fi

  wp_plugin_base_run_with_retry 3 2 "Download foundation asset: ${url}" \
    curl -fsSL \
    --connect-timeout 10 \
    --max-time 60 \
    --header "${header_name}: ${token}" \
    "$url" \
    -o "$destination_path"
}

read_fixture_or_api() {
  local fixture_path="$1"
  local url="$2"

  if [ -n "$fixture_path" ]; then
    if [ ! -f "$fixture_path" ]; then
      echo "Foundation API fixture not found: $fixture_path" >&2
      exit 1
    fi
    cat "$fixture_path"
    return
  fi

  case "$SOURCE_PROVIDER" in
    github|github-release)
      github_api_get "$url"
      ;;
    gitlab|gitlab-release)
      gitlab_api_get "$url"
      ;;
    *)
      echo "Unsupported foundation release source provider: ${SOURCE_PROVIDER}" >&2
      exit 1
      ;;
  esac
}

api_json() {
  local logical_key="$1"
  local url="$2"
  local fixture_path=""

  case "$logical_key" in
    release)
      fixture_path="${WP_PLUGIN_BASE_FOUNDATION_RELEASE_JSON:-}"
      ;;
    tag_ref)
      fixture_path="${WP_PLUGIN_BASE_FOUNDATION_TAG_REF_JSON:-${WP_PLUGIN_BASE_FOUNDATION_TAG_JSON:-}}"
      ;;
    tag_object)
      fixture_path="${WP_PLUGIN_BASE_FOUNDATION_TAG_OBJECT_JSON:-}"
      ;;
    compare)
      fixture_path="${WP_PLUGIN_BASE_FOUNDATION_COMPARE_JSON:-}"
      ;;
    commit_refs)
      fixture_path="${WP_PLUGIN_BASE_FOUNDATION_COMMIT_REFS_JSON:-}"
      ;;
    change_requests)
      fixture_path="${WP_PLUGIN_BASE_FOUNDATION_CHANGE_REQUESTS_JSON:-${WP_PLUGIN_BASE_FOUNDATION_PULLS_JSON:-}}"
      ;;
    *)
      echo "Unsupported foundation API logical key: ${logical_key}" >&2
      exit 1
      ;;
  esac

  read_fixture_or_api "$fixture_path" "$url"
}

download_release_asset() {
  local release_json="$1"
  local asset_name="$2"
  local destination_path="$3"
  local asset_url=""
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

  case "$SOURCE_PROVIDER" in
    github|github-release)
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

      github_asset_download "$asset_url" "$destination_path"
      ;;
    gitlab|gitlab-release)
      asset_url="$(
        printf '%s' "$release_json" | jq -r --arg name "$asset_name" '
          (.assets.links // [])
          | map(select(.name == $name))
          | .[0].url // empty
        ' | head -n 1
      )"

      if [ -z "$asset_url" ]; then
        echo "Foundation release ${VERSION} is missing required asset link: ${asset_name}" >&2
        exit 1
      fi

      gitlab_asset_download "$asset_url" "$destination_path"
      ;;
    *)
      echo "Unsupported foundation release source provider: ${SOURCE_PROVIDER}" >&2
      exit 1
      ;;
  esac
}

allowed_authors="${FOUNDATION_ALLOWED_RELEASE_AUTHORS:-github-actions[bot]}"
verify_sigstore_script="${WP_PLUGIN_BASE_VERIFY_SIGSTORE_SCRIPT:-$SCRIPT_DIR/../release/verify_sigstore_bundle.sh}"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORK_DIR"
}

trap cleanup EXIT

case "$SOURCE_PROVIDER" in
  github|github-release)
    release_json="$(api_json release "${SOURCE_API_BASE}/repos/${REFERENCE}/releases/tags/${VERSION}")"

    if [ "$(printf '%s' "$release_json" | jq -r '.draft')" != "false" ]; then
      echo "Foundation release ${VERSION} is still a draft." >&2
      exit 1
    fi

    if [ "$(printf '%s' "$release_json" | jq -r '.prerelease')" != "false" ]; then
      echo "Foundation release ${VERSION} is a prerelease." >&2
      exit 1
    fi

    release_author="$(printf '%s' "$release_json" | jq -r '.author.login // empty')"

    tag_ref_json="$(api_json tag_ref "${SOURCE_API_BASE}/repos/${REFERENCE}/git/ref/tags/${VERSION}")"
    tag_object_type="$(printf '%s' "$tag_ref_json" | jq -r '.object.type')"
    tag_object_sha="$(printf '%s' "$tag_ref_json" | jq -r '.object.sha')"

    if [ "$tag_object_type" = "tag" ]; then
      tag_object_json="$(api_json tag_object "${SOURCE_API_BASE}/repos/${REFERENCE}/git/tags/${tag_object_sha}")"
      commit_sha="$(printf '%s' "$tag_object_json" | jq -r '.object.sha')"
    else
      commit_sha="$tag_object_sha"
    fi

    # GitHub compare status is directional. To assert the release commit is on main,
    # compare main (base) against the release commit (head) and require behind/identical.
    compare_json="$(
      api_json compare "${SOURCE_API_BASE}/repos/${REFERENCE}/compare/main...${commit_sha}"
    )"
    compare_status="$(printf '%s' "$compare_json" | jq -r '.status')"

    if [ "$compare_status" != "behind" ] && [ "$compare_status" != "identical" ]; then
      echo "Foundation release ${VERSION} does not point to a commit on main." >&2
      exit 1
    fi

    change_requests_json="$(api_json change_requests "${SOURCE_API_BASE}/repos/${REFERENCE}/commits/${commit_sha}/pulls")"
    matching_count="$(
      printf '%s' "$change_requests_json" | jq -r --arg sha "$commit_sha" '
        map(
          select(
            .merged_at != null and
            .base.ref == "main" and
            (.head.ref | test("^(release|hotfix)/v[0-9]+\\.[0-9]+\\.[0-9]+$")) and
            .merge_commit_sha == $sha
          )
        ) | length
      '
    )"
    ;;
  gitlab|gitlab-release)
    gitlab_project_id="$(wp_plugin_base_provider_gitlab_project_id "$REFERENCE")"
    encoded_version="$(jq -rn --arg value "$VERSION" '$value | @uri')"
    release_json="$(api_json release "${SOURCE_API_BASE}/projects/${gitlab_project_id}/releases/${encoded_version}")"

    if [ "$(printf '%s' "$release_json" | jq -r '(.upcoming_release // false)')" != "false" ]; then
      echo "Foundation release ${VERSION} is still upcoming." >&2
      exit 1
    fi

    if [ "$(printf '%s' "$release_json" | jq -r '.released_at // empty')" = "" ]; then
      echo "Foundation release ${VERSION} is not published." >&2
      exit 1
    fi

    release_author="$(printf '%s' "$release_json" | jq -r '.author.username // .author.name // empty')"

    tag_json="$(api_json tag_ref "${SOURCE_API_BASE}/projects/${gitlab_project_id}/repository/tags/${encoded_version}")"
    commit_sha="$(printf '%s' "$tag_json" | jq -r '.commit.id // .target // empty')"
    if [ -z "$commit_sha" ]; then
      echo "Foundation release ${VERSION} is missing a tag commit SHA." >&2
      exit 1
    fi

    commit_refs_json="$(
      api_json commit_refs "${SOURCE_API_BASE}/projects/${gitlab_project_id}/repository/commits/${commit_sha}/refs?type=branch"
    )"
    if [ "$(printf '%s' "$commit_refs_json" | jq -r 'map(select(.type == "branch" and .name == "main")) | length')" -lt 1 ]; then
      echo "Foundation release ${VERSION} does not point to a commit on main." >&2
      exit 1
    fi

    change_requests_json="$(
      api_json change_requests "${SOURCE_API_BASE}/projects/${gitlab_project_id}/repository/commits/${commit_sha}/merge_requests?state=merged"
    )"
    matching_count="$(
      printf '%s' "$change_requests_json" | jq -r --arg sha "$commit_sha" '
        map(
          select(
            .state == "merged" and
            .target_branch == "main" and
            (.source_branch | test("^(release|hotfix)/v[0-9]+\\.[0-9]+\\.[0-9]+$")) and
            .merge_commit_sha == $sha
          )
        ) | length
      '
    )"
    ;;
  *)
    echo "Unsupported foundation release source provider: ${SOURCE_PROVIDER}" >&2
    exit 1
    ;;
esac

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

metadata_path="$WORK_DIR/dist-foundation-release.json"
sigstore_path="$WORK_DIR/dist-foundation-release.json.sigstore.json"

download_release_asset "$release_json" "dist-foundation-release.json" "$metadata_path"
download_release_asset "$release_json" "dist-foundation-release.json.sigstore.json" "$sigstore_path"

bash "$verify_sigstore_script" \
  "$REFERENCE" \
  "$metadata_path" \
  "$sigstore_path" \
  foundation \
  "$SOURCE_PROVIDER" \
  "$SOURCE_API_BASE" \
  "$SOURCE_SIGSTORE_ISSUER"

metadata_repository="$(jq -r '.repository // empty' "$metadata_path")"
metadata_version="$(jq -r '.version // empty' "$metadata_path")"
metadata_commit="$(jq -r '.commit // empty' "$metadata_path")"
metadata_source_provider="$(jq -r '.release_source.provider // empty' "$metadata_path")"
metadata_source_reference="$(jq -r '.release_source.reference // empty' "$metadata_path")"
metadata_source_api_base="$(jq -r '.release_source.api_base // empty' "$metadata_path")"

if [ -z "$metadata_source_provider" ] && [ -n "$metadata_repository" ]; then
  metadata_source_provider="github-release"
  metadata_source_reference="$metadata_repository"
  metadata_source_api_base="$(wp_plugin_base_provider_default_api_base github-release)"
fi

if [ "$metadata_source_provider" != "$SOURCE_PROVIDER" ]; then
  echo "Foundation release metadata provider ${metadata_source_provider} does not match ${SOURCE_PROVIDER}." >&2
  exit 1
fi

if [ "$metadata_source_reference" != "$REFERENCE" ]; then
  echo "Foundation release metadata reference ${metadata_source_reference} does not match ${REFERENCE}." >&2
  exit 1
fi

if [ "$metadata_source_api_base" != "$SOURCE_API_BASE" ]; then
  echo "Foundation release metadata API base ${metadata_source_api_base} does not match ${SOURCE_API_BASE}." >&2
  exit 1
fi

if [ "$SOURCE_PROVIDER" = "github-release" ] && [ -n "$metadata_repository" ] && [ "$metadata_repository" != "$REFERENCE" ]; then
  echo "Foundation release metadata repository ${metadata_repository} does not match ${REFERENCE}." >&2
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

if [ "$matching_count" -eq 0 ]; then
  echo "Foundation release ${VERSION} was not produced by a merged release or hotfix change request on main." >&2
  exit 1
fi

if [ -n "$OUTPUT_PATH" ]; then
  {
    echo "version=$VERSION"
    echo "commit_sha=$commit_sha"
    echo "source_provider=$SOURCE_PROVIDER"
    echo "source_reference=$REFERENCE"
    echo "source_api_base=$SOURCE_API_BASE"
  } >> "$OUTPUT_PATH"
fi

echo "Verified provenance for ${SOURCE_PROVIDER} ${REFERENCE} ${VERSION} (${commit_sha})"
