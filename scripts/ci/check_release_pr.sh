#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

if [ "$match_count" -lt 1 ]; then
  echo "Commit ${COMMIT_SHA} is not the merge commit of a merged release or hotfix PR for version ${VERSION}." >&2
  exit 1
fi

echo "Verified release commit ${COMMIT_SHA} for version ${VERSION}."
