#!/usr/bin/env bash

set -euo pipefail

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

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 1
fi

api_url="https://api.github.com/repos/${REPOSITORY}/commits/${COMMIT_SHA}/pulls"
response="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$api_url")"

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
