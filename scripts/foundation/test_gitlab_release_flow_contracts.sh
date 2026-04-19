#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

fixture="$(mktemp -d)"
origin_repo="$(mktemp -d)"
captured_body="$(mktemp)"

cleanup() {
  rm -rf "$fixture" "$origin_repo" "$captured_body"
}
trap cleanup EXIT

cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$fixture/"
mkdir -p "$fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$fixture/.wp-plugin-base/"

cat > "$fixture/.wp-plugin-base.env" <<'EOF'
FOUNDATION_RELEASE_SOURCE_PROVIDER=gitlab-release
FOUNDATION_RELEASE_SOURCE_REFERENCE=example-group/wp-plugin-base
FOUNDATION_RELEASE_SOURCE_API_BASE=https://gitlab.com/api/v4
FOUNDATION_VERSION=v1.5.0
AUTOMATION_PROVIDER=gitlab
AUTOMATION_API_BASE=https://gitlab.com/api/v4
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
PRODUCTION_ENVIRONMENT=production
CODEOWNERS_REVIEWERS=@example/platform
EOF

(
  cd "$fixture"
  git init >/dev/null
  git checkout -b main >/dev/null
  git config user.name tester
  git config user.email tester@example.invalid
  git add .
  git commit -m "Initial commit" >/dev/null
  git init --bare "$origin_repo/origin.git" >/dev/null
  git remote add origin "$origin_repo/origin.git"
  git push -u origin main >/dev/null
)

missing_tag_log="$(mktemp)"
if (
  cd "$fixture"
  WP_PLUGIN_BASE_ROOT="$fixture" CI_PROJECT_PATH=example-group/standard-plugin \
    bash "$ROOT_DIR/scripts/release/run_gitlab_release.sh" "9.9.9" ".wp-plugin-base.env"
) >"$missing_tag_log" 2>&1; then
  echo "run_gitlab_release unexpectedly passed without an existing tag." >&2
  exit 1
fi
grep -Fq 'requires an existing tag' "$missing_tag_log"
rm -f "$missing_tag_log"

cat > "$fixture/.wp-plugin-base/scripts/update/create_or_update_change_request.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cp "$5" "$WP_PLUGIN_BASE_CAPTURED_BODY"
EOF
chmod +x "$fixture/.wp-plugin-base/scripts/update/create_or_update_change_request.sh"

(
  cd "$fixture"
  WP_PLUGIN_BASE_ROOT="$fixture" \
    AUTOMATION_PROJECT_PATH=example-group/standard-plugin \
    WP_PLUGIN_BASE_CAPTURED_BODY="$captured_body" \
    bash "$fixture/.wp-plugin-base/scripts/release/prepare_release_change_request.sh" patch "" main ".wp-plugin-base.env" >/dev/null
)

grep -Fq 'create and push the release tag manually after merge' "$captured_body"
grep -Fq 'git tag ' "$captured_body"
grep -Fq 'git push origin ' "$captured_body"

release_body="$(mktemp)"
(
  cd "$fixture"
  WP_PLUGIN_BASE_ROOT="$fixture" \
    bash "$ROOT_DIR/scripts/release/generate_github_release_body.sh" "1.2.3" ".wp-plugin-base.env" >"$release_body"
)
grep -Fq 'GitLab also provides automatic source code archives' "$release_body"
if grep -Fq 'GitHub also provides automatic source code archives' "$release_body"; then
  echo "GitLab release body unexpectedly used GitHub-specific source archive text." >&2
  exit 1
fi
rm -f "$release_body"

echo "GitLab release flow contract tests passed."
