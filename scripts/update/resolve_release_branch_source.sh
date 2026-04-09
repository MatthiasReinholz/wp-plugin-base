#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

wp_plugin_base_require_commands "release branch source resolution" git gh

api_token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "$api_token" ]; then
  echo "GH_TOKEN or GITHUB_TOKEN is required." >&2
  exit 1
fi
export GH_TOKEN="$api_token"

if git ls-remote --exit-code --heads origin "$RELEASE_BRANCH" >/dev/null 2>&1; then
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
