#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/provider.sh
. "$ROOT_DIR/scripts/lib/provider.sh"

fixture_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$fixture_dir"
}
trap cleanup EXIT

cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$fixture_dir/"
mkdir -p "$fixture_dir/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$fixture_dir/.wp-plugin-base/"

cat > "$fixture_dir/.wp-plugin-base.env" <<'EOF'
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
PLUGIN_RUNTIME_UPDATE_PROVIDER=gitlab-release
PLUGIN_RUNTIME_UPDATE_SOURCE_URL=https://gitlab.com/example-group/standard-plugin
CODEOWNERS_REVIEWERS=@example/platform
EOF

cat >> "$fixture_dir/standard-plugin.php" <<'EOF'
require_once __DIR__ . '/lib/wp-plugin-base/wp-plugin-base-runtime-updater.php';
EOF

WP_PLUGIN_BASE_ROOT="$fixture_dir" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"

test -f "$fixture_dir/.gitlab-ci.yml"
test -f "$fixture_dir/.gitlab/CODEOWNERS"
test ! -e "$fixture_dir/.github/workflows/ci.yml"
test ! -e "$fixture_dir/.github/dependabot.yml"
test -f "$fixture_dir/lib/wp-plugin-base/wp-plugin-base-runtime-updater.php"
test -f "$fixture_dir/lib/wp-plugin-base/wp-plugin-base-github-updater.php"

grep -Fq "__PLUGIN_RUNTIME_UPDATE_PROVIDER__" "$fixture_dir/lib/wp-plugin-base/wp-plugin-base-runtime-updater.php" && {
  echo "Runtime updater template placeholders were not rendered." >&2
  exit 1
}
grep -Fq "gitlab-release" "$fixture_dir/lib/wp-plugin-base/wp-plugin-base-runtime-updater.php"
grep -Fq "https://gitlab.com/example-group/standard-plugin" "$fixture_dir/lib/wp-plugin-base/wp-plugin-base-runtime-updater.php"

WP_PLUGIN_BASE_ROOT="$fixture_dir" bash "$ROOT_DIR/scripts/ci/validate_project.sh" ".wp-plugin-base.env" "main"
if WP_PLUGIN_BASE_ROOT="$fixture_dir" WP_ORG_DEPLOY_ENABLED=true bash "$ROOT_DIR/scripts/ci/validate_project.sh" ".wp-plugin-base.env" "main" >/dev/null 2>&1; then
  echo "GitLab validation unexpectedly passed without deploy-environment acknowledgment." >&2
  exit 1
fi
WP_PLUGIN_BASE_ROOT="$fixture_dir" WP_ORG_DEPLOY_ENABLED=true WP_PLUGIN_BASE_GITLAB_DEPLOY_ENV_ACKNOWLEDGED=true bash "$ROOT_DIR/scripts/ci/validate_project.sh" ".wp-plugin-base.env" "main"
WP_PLUGIN_BASE_ROOT="$fixture_dir" bash "$ROOT_DIR/scripts/ci/build_zip.sh" ".wp-plugin-base.env"

gitlab_identity_regex="$(wp_plugin_base_provider_sigstore_identity_regex gitlab-release https://gitlab.com/api/v4 example-group/wp-plugin-base foundation)"
if ! printf '%s\n' 'https://gitlab.com/example-group/wp-plugin-base/.gitlab-ci.yml@refs/heads/main' | grep -Eq "$gitlab_identity_regex"; then
  echo "GitLab Sigstore identity regex did not match a canonical GitLab identity." >&2
  exit 1
fi

if [ "$(wp_plugin_base_provider_sigstore_oidc_issuer gitlab-release https://gitlab.com/api/v4)" != 'https://gitlab.com' ]; then
  echo "GitLab.com Sigstore issuer did not resolve to https://gitlab.com." >&2
  exit 1
fi

self_managed_gitlab_api_base="https:"
self_managed_gitlab_api_base="${self_managed_gitlab_api_base}//gitlab.example.com/api/v4"
if [ -n "$(wp_plugin_base_provider_sigstore_oidc_issuer gitlab-release "$self_managed_gitlab_api_base")" ]; then
  echo "Self-managed GitLab Sigstore issuer unexpectedly defaulted instead of requiring an explicit override." >&2
  exit 1
fi

zip_listing="$(unzip -Z1 "$fixture_dir/dist/standard-plugin.zip")"
printf '%s\n' "$zip_listing" | grep -q '^standard-plugin/lib/wp-plugin-base/wp-plugin-base-runtime-updater.php$'
if printf '%s\n' "$zip_listing" | grep -q '^standard-plugin/.gitlab-ci.yml$'; then
  echo "GitLab CI config leaked into the release package." >&2
  exit 1
fi
if printf '%s\n' "$zip_listing" | grep -q '^standard-plugin/.gitlab/'; then
  echo "GitLab metadata leaked into the release package." >&2
  exit 1
fi

echo "Validated GitLab automation and runtime updater support."
