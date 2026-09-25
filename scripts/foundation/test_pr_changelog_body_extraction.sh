#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

fixture="$(mktemp -d)"
fake_bin="$(mktemp -d)"
github_output="$(mktemp)"
gitlab_output="$(mktemp)"
github_error="$(mktemp)"
gitlab_error="$(mktemp)"

cleanup() {
  rm -rf "$fixture" "$fake_bin" "$github_output" "$gitlab_output" "$github_error" "$gitlab_error"
}
trap cleanup EXIT
echo "Starting PR changelog body extraction tests."

assert_output_contains() {
  local output_file="$1"
  local expected="$2"
  local provider="$3"

  if ! grep -Fq "$expected" "$output_file"; then
    echo "${provider} release notes did not contain expected entry: ${expected}" >&2
    echo "Actual ${provider} release notes:" >&2
    cat "$output_file" >&2
    exit 1
  fi
}

cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$fixture/"
mkdir -p "$fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$fixture/.wp-plugin-base/"
echo "Prepared PR changelog fixture."

cat > "$fixture/.wp-plugin-base.env" <<'EOF_CONFIG'
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=22
CHANGELOG_SOURCE=change_request_titles
EOF_CONFIG

(
  cd "$fixture"
  git init >/dev/null
  git branch -M main >/dev/null
  git config user.name tester
  git config user.email tester@example.invalid
  git config gc.auto 0
  git add .
  git commit -m "Initial commit" >/dev/null
  git tag 1.2.2
  printf '%s\n' "body extraction fixture" >> "$fixture/README.md"
  git add README.md
  git commit -m "Update fixture for changelog extraction" >/dev/null
  printf '%s\n' "empty section fallback fixture" >> "$fixture/README.md"
  git add README.md
  git commit -m "Add fallback coverage fixture commit" >/dev/null
)

fallback_sha="$(git -C "$fixture" rev-parse HEAD)"
head_sha="$(git -C "$fixture" rev-parse HEAD~1)"

cat > "$fake_bin/gh" <<EOF_GH
#!/usr/bin/env bash
cat <<'JSON'
[
  {
    "merged_at": "2026-04-22T00:00:00Z",
    "merge_commit_sha": "$head_sha",
    "title": "Update internal build metadata",
    "body": "## Changelog\n- Fix nonce verification edge case\n- Add opt-out toggle in admin settings\n- [ ] deferred checklist item\n\n## Notes\nNo follow-up required.",
    "labels": [{"name": "enhancement"}]
  },
  {
    "merged_at": "2026-04-22T00:05:00Z",
    "merge_commit_sha": "$fallback_sha",
    "title": "Tweak fallback title path",
    "body": "## Release Notes\n- none\n- n/a\n- [ ] deferred checklist item",
    "labels": [{"name": "performance"}]
  }
]
JSON
EOF_GH
chmod +x "$fake_bin/gh"
echo "Prepared GitHub provider fixture."

cat > "$fixture/gitlab-response.json" <<EOF_JSON
[
  {
    "merged_at": "2026-04-22T00:00:00Z",
    "merge_commit_sha": "$head_sha",
    "title": "Update automation defaults",
    "description": "## Changes\n- Tweak runtime guard defaults\n- [x] Dev docs cleanup for runtime guidance\n- _none_\n- [ ] deferred checklist item\n\n## Out of scope\nn/a",
    "labels": ["performance"]
  }
]
EOF_JSON

http_client_name='cu'"rl"
cat > "$fake_bin/$http_client_name" <<'EOF_CURL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$GITLAB_FIXTURE_ARGS"
header_file=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = '--header' ]; then
    shift
    case "$1" in
      @*) header_file="${1#@}" ;;
      *) echo 'Authentication must use a header file.' >&2; exit 1 ;;
    esac
  fi
  shift
done
[ -n "$header_file" ] && [ -f "$header_file" ]
[ "$(cat "$header_file")" = "$GITLAB_FIXTURE_EXPECTED_HEADER" ]
[ "$(LC_ALL=C ls -ld "$header_file" | cut -c 2-10)" = 'rw-------' ]
printf '%s\n' "$header_file" > "$GITLAB_FIXTURE_HEADER_PATH"
if [ "${GITLAB_FIXTURE_FAIL:-false}" = true ]; then
  echo 'Synthetic request failure.' >&2
  exit 22
fi
cat "$GITLAB_FIXTURE_RESPONSE"
EOF_CURL
chmod +x "$fake_bin/$http_client_name"
echo "Prepared GitLab provider fixture."

if ! PATH="$fake_bin:$PATH" \
  AUTOMATION_PROVIDER=github \
  GITHUB_REPOSITORY=example/standard-plugin \
  WP_PLUGIN_BASE_ROOT="$fixture" \
  bash -x "$ROOT_DIR/scripts/release/generate_release_notes_from_pr_titles.sh" "1.2.3" ".wp-plugin-base.env" > "$github_output" 2> "$github_error"; then
  echo "GitHub release-note generator failed:" >&2
  cat "$github_error" >&2
  exit 1
fi
echo "Generated GitHub release-note fixture output."

assert_output_contains "$github_output" '* Add - Add opt-out toggle in admin settings.' "GitHub"
assert_output_contains "$github_output" '* Fix - Fix nonce verification edge case.' "GitHub"
assert_output_contains "$github_output" '* Tweak - Tweak fallback title path.' "GitHub"
if grep -Fq 'Update internal build metadata' "$github_output"; then
  echo "Generator unexpectedly fell back to title despite a changelog body section." >&2
  exit 1
fi
if grep -Fq 'deferred checklist item' "$github_output"; then
  echo "Generator unexpectedly included unchecked task-list entries for GitHub release notes." >&2
  exit 1
fi

project_token='synthetic-project-release-note-token'
job_token='synthetic-job-release-note-token'
gitlab_args="$fixture/gitlab-args"
gitlab_header_path="$fixture/gitlab-header-path"
cat > "$fixture/expected-gitlab-notes" <<'EOF_NOTES'
* Tweak - Tweak runtime guard defaults.
* Dev - Dev docs cleanup for runtime guidance.
EOF_NOTES

for token_kind in project job; do
  project_token_value=''
  expected_header="JOB-TOKEN: $job_token"
  if [ "$token_kind" = project ]; then
    project_token_value="$project_token"
    expected_header="PRIVATE-TOKEN: $project_token"
  fi
  for request_fails in false true; do
    rm -f "$gitlab_args" "$gitlab_header_path"
    status=0
    PATH="$fake_bin:$PATH" \
      AUTOMATION_PROVIDER=gitlab \
      CI_PROJECT_PATH=example-group/standard-plugin \
      GITLAB_TOKEN="$project_token_value" CI_JOB_TOKEN="$job_token" \
      AUTOMATION_API_BASE=https://gitlab.com/api/v4 \
      WP_PLUGIN_BASE_ROOT="$fixture" \
      GITLAB_FIXTURE_ARGS="$gitlab_args" \
      GITLAB_FIXTURE_HEADER_PATH="$gitlab_header_path" \
      GITLAB_FIXTURE_EXPECTED_HEADER="$expected_header" \
      GITLAB_FIXTURE_RESPONSE="$fixture/gitlab-response.json" \
      GITLAB_FIXTURE_FAIL="$request_fails" \
      bash "$ROOT_DIR/scripts/release/generate_release_notes_from_pr_titles.sh" "1.2.3" ".wp-plugin-base.env" > "$gitlab_output" 2> "$gitlab_error" || status=$?

    for forbidden in "$project_token" "$job_token" 'PRIVATE-TOKEN:' 'JOB-TOKEN:'; do
      if grep -Fq "$forbidden" "$gitlab_output" "$gitlab_error" "$gitlab_args"; then
        echo "GitLab $token_kind authentication leaked into notes, diagnostics or process arguments." >&2
        exit 1
      fi
    done
    if [ ! -s "$gitlab_header_path" ] || [ -e "$(cat "$gitlab_header_path")" ]; then
      echo "GitLab $token_kind authentication file was not used and cleaned up." >&2
      exit 1
    fi
    if [ "$request_fails" = true ]; then
      if [ "$status" -eq 0 ] || [ -s "$gitlab_output" ]; then
        echo "GitLab request failure must fail without producing release notes." >&2
        exit 1
      fi
      assert_output_contains "$gitlab_error" 'Synthetic request failure.' 'GitLab failure'
    elif [ "$status" -ne 0 ] || [ -s "$gitlab_error" ] || ! cmp -s "$fixture/expected-gitlab-notes" "$gitlab_output"; then
      echo "GitLab $token_kind release notes did not match the expected notes exactly." >&2
      exit 1
    fi
  done
done
echo "GitLab project/job authentication, exact notes and failure cleanup passed."

echo "PR changelog body extraction tests passed."
