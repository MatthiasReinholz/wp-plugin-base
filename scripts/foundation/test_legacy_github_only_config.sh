#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/provider.sh
. "$ROOT_DIR/scripts/lib/provider.sh"

fixture="$(mktemp -d)"
project_outputs="$(mktemp)"
foundation_outputs="$(mktemp)"

cleanup() {
  rm -rf "$fixture" "$project_outputs" "$foundation_outputs"
}
trap cleanup EXIT

cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$fixture/"
mkdir -p "$fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$fixture/.wp-plugin-base/"

cat > "$fixture/.wp-plugin-base.env" <<'EOF'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.5.0
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
GITHUB_RELEASE_UPDATER_ENABLED=true
GITHUB_RELEASE_UPDATER_REPO_URL=https://github.com/example/standard-plugin
CHANGELOG_SOURCE=prs_titles
EOF

cat >> "$fixture/standard-plugin.php" <<'EOF'
require_once __DIR__ . '/lib/wp-plugin-base/wp-plugin-base-github-updater.php';
EOF

WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/validate_config.sh" --scope project .wp-plugin-base.env >/dev/null
WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/write_config_outputs.sh" project .wp-plugin-base.env "$project_outputs"
WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/write_config_outputs.sh" foundation .wp-plugin-base.env "$foundation_outputs"
WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" ".wp-plugin-base.env" "main"

grep -Fxq 'plugin_runtime_update_provider=github-release' "$project_outputs"
grep -Fxq 'plugin_runtime_update_source_url=https://github.com/example/standard-plugin' "$project_outputs"
grep -Fxq 'github_release_updater_enabled=true' "$project_outputs"
grep -Fxq 'github_release_updater_repo_url=https://github.com/example/standard-plugin' "$project_outputs"
grep -Fxq 'release_source_provider=github-release' "$foundation_outputs"
grep -Fxq 'release_source_reference=MatthiasReinholz/wp-plugin-base' "$foundation_outputs"
grep -Fxq 'repository=MatthiasReinholz/wp-plugin-base' "$foundation_outputs"
test -f "$fixture/.github/workflows/update-foundation.yml"
test -f "$fixture/lib/wp-plugin-base/wp-plugin-base-runtime-updater.php"
test -f "$fixture/lib/wp-plugin-base/wp-plugin-base-github-updater.php"
grep -Fq 'github-release' "$fixture/lib/wp-plugin-base/wp-plugin-base-runtime-updater.php"
grep -Fq 'https://github.com/example/standard-plugin' "$fixture/lib/wp-plugin-base/wp-plugin-base-runtime-updater.php"

normalized_changelog_source="$(
  WP_PLUGIN_BASE_ROOT="$fixture" bash -c '
    source scripts/lib/load_config.sh
    wp_plugin_base_load_config ".wp-plugin-base.env" >/dev/null
    printf "%s\n" "$CHANGELOG_SOURCE"
  '
)"
if [ "$normalized_changelog_source" != "change_request_titles" ]; then
  echo "Legacy CHANGELOG_SOURCE=prs_titles was not normalized to change_request_titles." >&2
  exit 1
fi

github_identity_regex="$(wp_plugin_base_provider_sigstore_identity_regex github-release https://api.github.com MatthiasReinholz/wp-plugin-base foundation)"
if ! printf '%s\n' 'https://github.com/MatthiasReinholz/wp-plugin-base/.github/workflows/release-foundation.yml@refs/heads/main' | grep -Eq "$github_identity_regex"; then
  echo "GitHub Sigstore identity regex did not match a canonical GitHub identity." >&2
  exit 1
fi

if [ "$(wp_plugin_base_provider_sigstore_oidc_issuer github-release https://api.github.com)" != 'https://token.actions.githubusercontent.com' ]; then
  echo "GitHub Sigstore issuer did not resolve to the expected GitHub OIDC issuer." >&2
  exit 1
fi

echo "Legacy GitHub-only config compatibility tests passed."
