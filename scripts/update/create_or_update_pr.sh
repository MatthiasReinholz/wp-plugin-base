#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "pull request automation" git gh jq

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
AUTH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
LAST_PUSH_ERROR_KIND=""

configure_git_remote_auth() {
  local origin_url
  local auth_header
  local auth_payload

  [ -n "$AUTH_TOKEN" ] || return 0

  origin_url="$(git remote get-url origin)"
  case "$origin_url" in
    https://github.com/*|http://github.com/*|git@github.com:*|ssh://git@github.com/*)
      auth_payload="$(printf 'x-access-token:%s' "$AUTH_TOKEN" | base64 | tr -d '\n')"
      auth_header="AUTHORIZATION: basic ${auth_payload}"
      # actions/checkout may have already configured an Authorization extraheader.
      # Clear any inherited values first so Git does not send duplicate headers.
      git config --local --unset-all http.https://github.com/.extraheader >/dev/null 2>&1 || true
      git config --local http.https://github.com/.extraheader "$auth_header"
      case "$origin_url" in
        git@github.com:*|ssh://git@github.com/*)
          git remote set-url origin "https://github.com/${REPO}.git"
          ;;
      esac
      ;;
  esac
}

has_staged_workflow_changes() {
  git diff --cached --name-only | grep -Eq '^\.github/workflows/[^[:space:]]+\.(yml|yaml)$'
}

print_workflow_push_guidance() {
  cat >&2 <<'EOF'
GitHub rejected this push because the staged update includes workflow files under .github/workflows/ and the current token cannot modify workflows.

Resolution:
- configure the repository or organization secret `WP_PLUGIN_BASE_PR_TOKEN`
- grant that token repository write access for contents, pull requests, and workflows
- rerun the workflow after the secret is available

New wp-plugin-base updater templates automatically prefer `WP_PLUGIN_BASE_PR_TOKEN` when present.
Existing child repositories on older foundation versions need a one-time manual workflow bootstrap so `update-foundation.yml` passes that secret through.
EOF
}

run_git_push() {
  local push_log
  push_log="$(mktemp)"
  LAST_PUSH_ERROR_KIND=""

  if git push "$@" >"$push_log" 2>&1; then
    rm -f "$push_log"
    return 0
  fi

  cat "$push_log" >&2
  if grep -Fq 'refusing to allow a GitHub App to create or update workflow' "$push_log"; then
    LAST_PUSH_ERROR_KIND="workflow-permission"
  fi
  rm -f "$push_log"
  return 1
}

configure_git_remote_auth

git fetch origin "$BRANCH_NAME" >/dev/null 2>&1 || true

if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
  git checkout "$BRANCH_NAME" >/dev/null
elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCH_NAME"; then
  git checkout -b "$BRANCH_NAME" --track "origin/$BRANCH_NAME" >/dev/null
else
  git checkout -b "$BRANCH_NAME" >/dev/null
fi

if [ -n "${GIT_ADD_PATHS:-}" ]; then
  declare -a stage_paths=()
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -e "$path" ] || git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
      stage_paths+=("$path")
    fi
  done < <(wp_plugin_base_csv_to_lines "$GIT_ADD_PATHS")

  if [ "${#stage_paths[@]}" -eq 0 ]; then
    echo "GIT_ADD_PATHS did not match any existing or tracked paths." >&2
    exit 1
  fi

  git add -A -- "${stage_paths[@]}"
else
  git add -A
fi

changes_committed=false
workflow_changes_committed=false

if ! git diff --cached --quiet; then
  if has_staged_workflow_changes; then
    workflow_changes_committed=true
  fi

  git commit -m "$COMMIT_MESSAGE"
  changes_committed=true
  if ! run_git_push origin "HEAD:$BRANCH_NAME"; then
    if [ "$LAST_PUSH_ERROR_KIND" = "workflow-permission" ] && [ "$workflow_changes_committed" = true ]; then
      print_workflow_push_guidance
      exit 1
    fi
    echo "Non-fast-forward push for $BRANCH_NAME; retrying with --force-with-lease." >&2
    if ! run_git_push --force-with-lease origin "HEAD:$BRANCH_NAME"; then
      if [ "$LAST_PUSH_ERROR_KIND" = "workflow-permission" ] && [ "$workflow_changes_committed" = true ]; then
        print_workflow_push_guidance
      fi
      exit 1
    fi
  fi
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
