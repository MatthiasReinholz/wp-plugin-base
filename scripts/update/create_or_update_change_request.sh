#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

BRANCH_NAME="${1:-}"
BASE_BRANCH="${2:-}"
REQUEST_TITLE="${3:-}"
COMMIT_MESSAGE="${4:-}"
BODY_FILE="${5:-}"

if [ -z "$BRANCH_NAME" ] || [ -z "$BASE_BRANCH" ] || [ -z "$REQUEST_TITLE" ] || [ -z "$COMMIT_MESSAGE" ] || [ -z "$BODY_FILE" ]; then
  echo "Usage: $0 branch-name base-branch title commit-message body-file" >&2
  exit 1
fi

if [ ! -f "$BODY_FILE" ]; then
  echo "Change-request body file not found: $BODY_FILE" >&2
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

if [ -n "${GIT_ADD_PATHS:-}" ]; then
  declare -a stage_paths=()
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -e "$path" ] || git -C "$ROOT_DIR" ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
      stage_paths+=("$path")
    fi
  done < <(wp_plugin_base_csv_to_lines "$GIT_ADD_PATHS")

  if [ "${#stage_paths[@]}" -eq 0 ]; then
    echo "GIT_ADD_PATHS did not match any existing or tracked paths." >&2
    exit 1
  fi

  git -C "$ROOT_DIR" add -A -- "${stage_paths[@]}"
else
  git -C "$ROOT_DIR" add -A
fi

changes_committed=false
workflow_changes_staged=false

if git -C "$ROOT_DIR" diff --cached --name-only -- '.github/workflows/*' '.github/actions/*' | grep -q .; then
  workflow_changes_staged=true
fi

print_github_workflow_scope_guidance() {
  if [ "$AUTOMATION_PROVIDER" != "github" ] || [ "$workflow_changes_staged" != true ]; then
    return
  fi

  cat >&2 <<'EOF'
GitHub automation is trying to push or open a pull request that includes workflow changes.
If this token does not have workflows scope, GitHub will reject the operation.
Provide a token with workflows scope via WP_PLUGIN_BASE_PR_TOKEN, or remove the workflow-file edits from this change request.
EOF
}

configure_github_git_auth() {
  local token=""
  local basic_auth=""

  if [ "$AUTOMATION_PROVIDER" != "github" ]; then
    return
  fi

  token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  if [ -z "$token" ]; then
    return
  fi

  basic_auth="$(printf 'x-access-token:%s' "$token" | base64 | tr -d '\n')"
  git -C "$ROOT_DIR" config --local --unset-all http.https://github.com/.extraheader >/dev/null 2>&1 || true
  git -C "$ROOT_DIR" config --local --add http.https://github.com/.extraheader "AUTHORIZATION: basic ${basic_auth}"
}

git_push_with_auth() {
  local token=""
  local scheme=""
  local rewrite_base=""

  if [ "$AUTOMATION_PROVIDER" = "github" ]; then
    token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    if [ -n "$token" ]; then
      configure_github_git_auth
      scheme="https:"
      rewrite_base="${scheme}//x-access-token:${token}"
      rewrite_base="${rewrite_base}@github.com/"
      git -C "$ROOT_DIR" \
        -c "url.${rewrite_base}.insteadOf=${scheme}//github.com/" \
        push "$@"
      return
    fi
  fi

  git -C "$ROOT_DIR" push "$@"
}

configure_github_git_auth
git -C "$ROOT_DIR" fetch origin "$BRANCH_NAME" >/dev/null 2>&1 || true

if git -C "$ROOT_DIR" show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
  git -C "$ROOT_DIR" checkout "$BRANCH_NAME" >/dev/null
elif git -C "$ROOT_DIR" show-ref --verify --quiet "refs/remotes/origin/$BRANCH_NAME"; then
  git -C "$ROOT_DIR" checkout -b "$BRANCH_NAME" --track "origin/$BRANCH_NAME" >/dev/null
else
  git -C "$ROOT_DIR" checkout -b "$BRANCH_NAME" >/dev/null
fi

if ! git -C "$ROOT_DIR" diff --cached --quiet; then
  git -C "$ROOT_DIR" commit -m "$COMMIT_MESSAGE"
  changes_committed=true
  push_output=""
  if ! push_output="$(git_push_with_auth origin "HEAD:$BRANCH_NAME" 2>&1)"; then
    if printf '%s' "$push_output" | grep -Eqi 'workflow|workflows|resource not accessible by integration|refusing to allow'; then
      printf '%s\n' "$push_output" >&2
      print_github_workflow_scope_guidance
      exit 1
    fi
    echo "Non-fast-forward push for $BRANCH_NAME; retrying with --force-with-lease." >&2
    if ! push_output="$(git_push_with_auth --force-with-lease origin "HEAD:$BRANCH_NAME" 2>&1)"; then
      printf '%s\n' "$push_output" >&2
      if printf '%s' "$push_output" | grep -Eqi 'workflow|workflows|resource not accessible by integration|refusing to allow'; then
        print_github_workflow_scope_guidance
      fi
      exit 1
    fi
  fi
fi

change_request_number=""
change_request_url=""
change_request_operation="none"

case "$AUTOMATION_PROVIDER" in
  github)
    wp_plugin_base_require_commands "pull request automation" gh jq

    repo="${GITHUB_REPOSITORY:-}"
    if [ -z "$repo" ]; then
      remote_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
      repo="$(wp_plugin_base_provider_infer_reference_from_remote github "$remote_url" || true)"
    fi
    if [ -z "$repo" ]; then
      echo "Unable to resolve GitHub repository for change-request automation." >&2
      exit 1
    fi

    owner="${GITHUB_REPOSITORY_OWNER:-${repo%%/*}}"
    pr_json="$(gh pr list --repo "$repo" --state open --head "$owner:$BRANCH_NAME" --base "$BASE_BRANCH" --json number,url --limit 1)"
    change_request_number="$(printf '%s' "$pr_json" | jq -r '.[0].number // empty')"
    change_request_url="$(printf '%s' "$pr_json" | jq -r '.[0].url // empty')"

    if [ -n "$change_request_number" ]; then
      gh pr edit "$change_request_number" --repo "$repo" --title "$REQUEST_TITLE" --body-file "$BODY_FILE" >/dev/null
      if [ "$changes_committed" = true ]; then
        change_request_operation="updated"
      fi
    elif [ "$changes_committed" = true ]; then
      create_output=""
      if ! create_output="$(gh pr create --repo "$repo" --base "$BASE_BRANCH" --head "$BRANCH_NAME" --title "$REQUEST_TITLE" --body-file "$BODY_FILE" 2>&1)"; then
        printf '%s\n' "$create_output" >&2
        if printf '%s' "$create_output" | grep -Eqi 'workflow|workflows|resource not accessible by integration|refusing to allow'; then
          print_github_workflow_scope_guidance
        fi
        exit 1
      fi
      change_request_url="$create_output"
      change_request_number="$(basename "$change_request_url")"
      change_request_operation="created"
    fi
    ;;
  gitlab)
    wp_plugin_base_require_commands "merge request automation" curl jq

    project_reference="${CI_PROJECT_PATH:-${AUTOMATION_PROJECT_PATH:-}}"
    if [ -z "$project_reference" ]; then
      remote_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
      project_reference="$(wp_plugin_base_provider_infer_reference_from_remote gitlab "$remote_url" || true)"
    fi
    if [ -z "$project_reference" ]; then
      echo "Unable to resolve GitLab project path for change-request automation." >&2
      exit 1
    fi

    gitlab_project_id="$(wp_plugin_base_provider_gitlab_project_id "$project_reference")"
    gitlab_token="${GITLAB_TOKEN:-${CI_JOB_TOKEN:-}}"
    if [ -z "$gitlab_token" ]; then
      echo "GITLAB_TOKEN or CI_JOB_TOKEN is required for GitLab merge-request automation." >&2
      exit 1
    fi

    gitlab_auth_header_name="PRIVATE-TOKEN"
    if [ -z "${GITLAB_TOKEN:-}" ] && [ -n "${CI_JOB_TOKEN:-}" ]; then
      gitlab_auth_header_name="JOB-TOKEN"
    fi

    gitlab_api() {
      local method="$1"
      local path="$2"
      shift 2 || true

      curl -fsSL \
        --request "$method" \
        --connect-timeout 10 \
        --max-time 60 \
        --header "${gitlab_auth_header_name}: ${gitlab_token}" \
        "$@" \
        "${AUTOMATION_API_BASE}/projects/${gitlab_project_id}${path}"
    }

    existing_json="$(
      gitlab_api GET "/merge_requests?state=opened&source_branch=${BRANCH_NAME}&target_branch=${BASE_BRANCH}&per_page=1"
    )"
    change_request_number="$(printf '%s' "$existing_json" | jq -r '.[0].iid // empty')"
    change_request_url="$(printf '%s' "$existing_json" | jq -r '.[0].web_url // empty')"

    if [ -n "$change_request_number" ]; then
      gitlab_api PUT "/merge_requests/${change_request_number}" \
        --data-urlencode "title=${REQUEST_TITLE}" \
        --data-urlencode "description@${BODY_FILE}" >/dev/null
      if [ "$changes_committed" = true ]; then
        change_request_operation="updated"
      fi
    elif [ "$changes_committed" = true ]; then
      created_json="$(
        gitlab_api POST "/merge_requests" \
          --data-urlencode "source_branch=${BRANCH_NAME}" \
          --data-urlencode "target_branch=${BASE_BRANCH}" \
          --data-urlencode "title=${REQUEST_TITLE}" \
          --data-urlencode "description@${BODY_FILE}"
      )"
      change_request_number="$(printf '%s' "$created_json" | jq -r '.iid // empty')"
      change_request_url="$(printf '%s' "$created_json" | jq -r '.web_url // empty')"
      change_request_operation="created"
    fi
    ;;
  *)
    echo "Unsupported AUTOMATION_PROVIDER: $AUTOMATION_PROVIDER" >&2
    exit 1
    ;;
esac

{
  echo "change_request_number=$change_request_number"
  echo "change_request_url=$change_request_url"
  echo "change_request_operation=$change_request_operation"
  echo "pull_request_number=$change_request_number"
  echo "pull_request_url=$change_request_url"
  echo "pull_request_operation=$change_request_operation"
} >> "${GITHUB_OUTPUT:-/dev/null}"
