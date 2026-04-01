#!/usr/bin/env bash

set -euo pipefail

BRANCH_NAME="${1:-}"
BASE_BRANCH="${2:-}"
PR_TITLE="${3:-}"
COMMIT_MESSAGE="${4:-}"
BODY_FILE="${5:-}"

if [ -z "$BRANCH_NAME" ] || [ -z "$BASE_BRANCH" ] || [ -z "$PR_TITLE" ] || [ -z "$COMMIT_MESSAGE" ] || [ -z "$BODY_FILE" ]; then
  echo "Usage: $0 branch-name base-branch pr-title commit-message body-file" >&2
  exit 1
fi

if [ ! -f "$BODY_FILE" ]; then
  echo "PR body file not found: $BODY_FILE" >&2
  exit 1
fi

REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
OWNER="${GITHUB_REPOSITORY_OWNER:-${REPO%%/*}}"

git checkout -B "$BRANCH_NAME" >/dev/null

git add -A
changes_committed=false

if ! git diff --cached --quiet; then
  git commit -m "$COMMIT_MESSAGE"
  changes_committed=true
  git push --force-with-lease origin "HEAD:$BRANCH_NAME"
fi

pr_json="$(gh pr list --repo "$REPO" --state open --head "$OWNER:$BRANCH_NAME" --base "$BASE_BRANCH" --json number,url --limit 1)"
pr_number="$(printf '%s' "$pr_json" | jq -r '.[0].number // empty')"
pr_url="$(printf '%s' "$pr_json" | jq -r '.[0].url // empty')"
pr_operation="none"

if [ -n "$pr_number" ]; then
  gh pr edit "$pr_number" --repo "$REPO" --title "$PR_TITLE" --body-file "$BODY_FILE" >/dev/null
  if [ "$changes_committed" = true ]; then
    pr_operation="updated"
  fi
elif [ "$changes_committed" = true ]; then
  pr_url="$(gh pr create --repo "$REPO" --base "$BASE_BRANCH" --head "$BRANCH_NAME" --title "$PR_TITLE" --body-file "$BODY_FILE")"
  pr_number="$(basename "$pr_url")"
  pr_operation="created"
fi

{
  echo "pull_request_number=$pr_number"
  echo "pull_request_url=$pr_url"
  echo "pull_request_operation=$pr_operation"
} >> "$GITHUB_OUTPUT"
