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
  git checkout -b main >/dev/null
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

http_client_name='cu'"rl"
cat > "$fake_bin/$http_client_name" <<EOF_CURL
#!/usr/bin/env sh
cat <<'JSON'
[
  {
    "merged_at": "2026-04-22T00:00:00Z",
    "merge_commit_sha": "$head_sha",
    "title": "Update automation defaults",
    "description": "## Changes\n- Tweak runtime guard defaults\n- [x] Dev docs cleanup for runtime guidance\n- _none_\n- [ ] deferred checklist item\n\n## Out of scope\nn/a",
    "labels": ["performance"]
  }
]
JSON
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

if ! PATH="$fake_bin:$PATH" \
  AUTOMATION_PROVIDER=gitlab \
  CI_PROJECT_PATH=example-group/standard-plugin \
  GITLAB_TOKEN=test-token \
  AUTOMATION_API_BASE=https://gitlab.com/api/v4 \
  WP_PLUGIN_BASE_ROOT="$fixture" \
  bash -x "$ROOT_DIR/scripts/release/generate_release_notes_from_pr_titles.sh" "1.2.3" ".wp-plugin-base.env" > "$gitlab_output" 2> "$gitlab_error"; then
  echo "GitLab release-note generator failed:" >&2
  cat "$gitlab_error" >&2
  exit 1
fi
echo "Generated GitLab release-note fixture output."

assert_output_contains "$gitlab_output" '* Tweak - Tweak runtime guard defaults.' "GitLab"
assert_output_contains "$gitlab_output" '* Dev - Dev docs cleanup for runtime guidance.' "GitLab"
if grep -Fq 'Update automation defaults' "$gitlab_output"; then
  echo "GitLab generator unexpectedly fell back to title despite a release notes section." >&2
  exit 1
fi
if grep -Fq 'deferred checklist item' "$gitlab_output"; then
  echo "Generator unexpectedly included unchecked task-list entries for GitLab release notes." >&2
  exit 1
fi
if grep -Fq '_none_' "$gitlab_output" || grep -Fq 'n/a' "$gitlab_output"; then
  echo "Generator unexpectedly included placeholder release-note entries." >&2
  exit 1
fi

echo "PR changelog body extraction tests passed."
