#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

REPOSITORY="${1:-${GITHUB_REPOSITORY:-}}"
REPOSITORY_OWNER="${2:-${GITHUB_REPOSITORY_OWNER:-}}"
RELEASE_BRANCH="${3:-}"
BASE_REF="${4:-}"
OUTPUT_PATH="${5:-${GITHUB_OUTPUT:-}}"

if [ -z "$REPOSITORY" ] || [ -z "$REPOSITORY_OWNER" ] || [ -z "$RELEASE_BRANCH" ] || [ -z "$BASE_REF" ] || [ -z "$OUTPUT_PATH" ]; then
  echo "Usage: $0 repository repository-owner release-branch base-ref output-path" >&2
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

case "$AUTOMATION_PROVIDER" in
  github)
    wp_plugin_base_require_commands "release branch source resolution" git gh

    api_token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    if [ -z "$api_token" ]; then
      echo "GH_TOKEN or GITHUB_TOKEN is required." >&2
      exit 1
    fi
    export GH_TOKEN="$api_token"
    ;;
  gitlab)
    wp_plugin_base_require_commands "release branch source resolution" git curl jq
    ;;
  *)
    echo "Unsupported AUTOMATION_PROVIDER: $AUTOMATION_PROVIDER" >&2
    exit 1
    ;;
esac

if git ls-remote --exit-code --heads origin "$RELEASE_BRANCH" >/dev/null 2>&1; then
  open_pr_count=""

  case "$AUTOMATION_PROVIDER" in
    github)
      open_pr_count="$(
        gh pr list \
          --repo "$REPOSITORY" \
          --state open \
          --head "${REPOSITORY_OWNER}:${RELEASE_BRANCH}" \
          --base "$BASE_REF" \
          --json number \
          --limit 1 \
          --jq 'length'
      )"
      ;;
    gitlab)
      gitlab_project_id="$(wp_plugin_base_provider_gitlab_project_id "$REPOSITORY")"
      gitlab_token="${GITLAB_TOKEN:-${CI_JOB_TOKEN:-}}"
      if [ -z "$gitlab_token" ]; then
        echo "GITLAB_TOKEN or CI_JOB_TOKEN is required." >&2
        exit 1
      fi
      gitlab_auth_header_name="PRIVATE-TOKEN"
      if [ -z "${GITLAB_TOKEN:-}" ] && [ -n "${CI_JOB_TOKEN:-}" ]; then
        gitlab_auth_header_name="JOB-TOKEN"
      fi

      open_pr_count="$(
        curl -fsSL \
          --connect-timeout 10 \
          --max-time 60 \
          --header "${gitlab_auth_header_name}: ${gitlab_token}" \
          "${AUTOMATION_API_BASE}/projects/${gitlab_project_id}/merge_requests?state=opened&source_branch=${RELEASE_BRANCH}&target_branch=${BASE_REF}&per_page=1" \
          | jq 'length'
      )"
      ;;
  esac

  if [ "$open_pr_count" -gt 0 ]; then
    {
      echo "branch_exists=true"
      echo "ref=$RELEASE_BRANCH"
      echo "open_pr_exists=true"
    } >> "$OUTPUT_PATH"
    echo "Refreshing existing release branch $RELEASE_BRANCH."
    exit 0
  fi

  {
    echo "branch_exists=true"
    echo "ref=$BASE_REF"
    echo "open_pr_exists=false"
  } >> "$OUTPUT_PATH"
  echo "Existing release branch $RELEASE_BRANCH has no open PR. Recreating it from $BASE_REF."
  exit 0
fi

{
  echo "ref=$BASE_REF"
  echo "branch_exists=false"
  echo "open_pr_exists=false"
} >> "$OUTPUT_PATH"
echo "Preparing a new release branch from $BASE_REF."
