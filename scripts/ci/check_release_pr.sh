#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "release pull request verification" curl jq

REPOSITORY="${1:-}"
VERSION="${2:-}"
COMMIT_SHA="${3:-}"

if [ -z "$REPOSITORY" ] || [ -z "$VERSION" ] || [ -z "$COMMIT_SHA" ]; then
  echo "Usage: $0 owner/repo x.y.z commit-sha" >&2
  exit 1
fi

ROOT_DIR="$(wp_plugin_base_root)"
ROOT_DIR="$(cd "$ROOT_DIR" && pwd -P)"
DEFAULT_CONFIG_PATH="${WP_PLUGIN_BASE_CONFIG:-.wp-plugin-base.env}"
if [ -f "$(wp_plugin_base_config_path "$ROOT_DIR" "$DEFAULT_CONFIG_PATH")" ]; then
  wp_plugin_base_load_config "$DEFAULT_CONFIG_PATH"
else
  AUTOMATION_PROVIDER="${AUTOMATION_PROVIDER:-github}"
  AUTOMATION_API_BASE="${AUTOMATION_API_BASE:-$(wp_plugin_base_provider_default_api_base "$AUTOMATION_PROVIDER")}"
fi

AUTOMATION_PROVIDER="${AUTOMATION_PROVIDER:-github}"
AUTOMATION_API_BASE="${AUTOMATION_API_BASE:-$(wp_plugin_base_provider_default_api_base "$AUTOMATION_PROVIDER")}"

response=""

case "$AUTOMATION_PROVIDER" in
  github)
    if [ -z "${GITHUB_TOKEN:-}" ]; then
      echo "GITHUB_TOKEN is required." >&2
      exit 1
    fi

    api_url="https://api.github.com/repos/${REPOSITORY}/commits/${COMMIT_SHA}/pulls"
    response="$(
      wp_plugin_base_run_with_retry 3 2 "Fetch release PR metadata for ${COMMIT_SHA}" \
        curl -fsSL \
        --connect-timeout 10 \
        --max-time 60 \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$api_url"
    )"
    match_count="$(
      printf '%s' "$response" | jq --arg version "$VERSION" --arg sha "$COMMIT_SHA" '
        map(
          select(
            .merged_at != null and
            .base.ref == "main" and
            (.head.ref == ("release/" + $version) or .head.ref == ("hotfix/" + $version)) and
            .merge_commit_sha == $sha
          )
        ) | length
      '
    )"
    ;;
  gitlab)
    wp_plugin_base_require_commands "release merge request verification" curl jq
    gitlab_token="${GITLAB_TOKEN:-${CI_JOB_TOKEN:-}}"
    if [ -z "$gitlab_token" ]; then
      echo "GITLAB_TOKEN or CI_JOB_TOKEN is required." >&2
      exit 1
    fi
    gitlab_auth_header_name="PRIVATE-TOKEN"
    if [ -z "${GITLAB_TOKEN:-}" ] && [ -n "${CI_JOB_TOKEN:-}" ]; then
      gitlab_auth_header_name="JOB-TOKEN"
    fi
    gitlab_project_id="$(wp_plugin_base_provider_gitlab_project_id "$REPOSITORY")"
    api_url="${AUTOMATION_API_BASE}/projects/${gitlab_project_id}/repository/commits/${COMMIT_SHA}/merge_requests?state=merged"
    response="$(
      wp_plugin_base_run_with_retry 3 2 "Fetch release MR metadata for ${COMMIT_SHA}" \
        curl -fsSL \
        --connect-timeout 10 \
        --max-time 60 \
        --header "${gitlab_auth_header_name}: ${gitlab_token}" \
        "$api_url"
    )"
    match_count="$(
      printf '%s' "$response" | jq --arg version "$VERSION" --arg sha "$COMMIT_SHA" '
        map(
          select(
            .state == "merged" and
            .target_branch == "main" and
            (.source_branch == ("release/" + $version) or .source_branch == ("hotfix/" + $version)) and
            .merge_commit_sha == $sha
          )
        ) | length
      '
    )"
    ;;
  *)
    echo "Unsupported AUTOMATION_PROVIDER: $AUTOMATION_PROVIDER" >&2
    exit 1
    ;;
esac

if [ "$match_count" -lt 1 ]; then
  echo "Commit ${COMMIT_SHA} is not the merge commit of a merged release or hotfix PR for version ${VERSION}." >&2
  exit 1
fi

echo "Verified release commit ${COMMIT_SHA} for version ${VERSION}."
