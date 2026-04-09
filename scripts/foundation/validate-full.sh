#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "full foundation validation" git php node ruby perl rsync zip unzip jq docker

quality_fixture=""
strict_plugin_check_fixture=""
security_pack_skip_fixture=""
custom_suppressions_fixture=""
missing_workflow_fixture=""
missing_managed_file_fixture=""
metadata_fixture=""
deploy_fixture=""
wp_build_fixture=""
pot_fixture=""

cleanup() {
  rm -rf "$quality_fixture" "$strict_plugin_check_fixture" "$security_pack_skip_fixture" "$custom_suppressions_fixture" "$missing_workflow_fixture" "$missing_managed_file_fixture" "$metadata_fixture" "$deploy_fixture" "$wp_build_fixture" "$pot_fixture"
}

trap cleanup EXIT

bash "$ROOT_DIR/scripts/foundation/validate.sh"

quality_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$quality_fixture/"
mkdir -p "$quality_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$quality_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$quality_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_PLUGIN_BASE_ROOT="$quality_fixture" bash "$ROOT_DIR/scripts/ci/validate_wordpress_readiness.sh" "" "release/1.3.0"

strict_plugin_check_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$strict_plugin_check_fixture/"
mkdir -p "$strict_plugin_check_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$strict_plugin_check_fixture/.wp-plugin-base/"
cat >> "$strict_plugin_check_fixture/.wp-plugin-base.env" <<'EOF'
WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS=true
WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES=security
EOF
WP_PLUGIN_BASE_ROOT="$strict_plugin_check_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_PLUGIN_BASE_ROOT="$strict_plugin_check_fixture" bash "$ROOT_DIR/scripts/ci/validate_wordpress_readiness.sh" "" "release/1.3.0"

security_pack_skip_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$security_pack_skip_fixture/"
mkdir -p "$security_pack_skip_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$security_pack_skip_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$security_pack_skip_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
skip_output="$(
WP_PLUGIN_BASE_ROOT="$security_pack_skip_fixture" \
    WP_PLUGIN_BASE_SECURITY_PACK_SKIP_SEMGREP=true \
    bash "$ROOT_DIR/scripts/ci/run_security_pack.sh" ""
)"
grep -Fq 'Semgrep pass is delegated to a separate step; skipping Semgrep execution in security pack.' <<<"$skip_output"
test ! -e "$security_pack_skip_fixture/dist/semgrep-security.sarif"

custom_suppressions_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$custom_suppressions_fixture/"
mkdir -p "$custom_suppressions_fixture/.wp-plugin-base"
cat >> "$custom_suppressions_fixture/.wp-plugin-base.env" <<'EOF'
WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE=.security/custom-security-suppressions.json
EOF
rsync -a --exclude '.git' "$ROOT_DIR/" "$custom_suppressions_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$custom_suppressions_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
test -f "$custom_suppressions_fixture/.security/custom-security-suppressions.json"
test ! -e "$custom_suppressions_fixture/.wp-plugin-base-security-suppressions.json"
managed_paths_output="$(WP_PLUGIN_BASE_ROOT="$custom_suppressions_fixture" bash "$ROOT_DIR/scripts/ci/list_managed_files.sh" ".wp-plugin-base.env")"
grep -Fxq '.security/custom-security-suppressions.json' <<<"$managed_paths_output"
grep -Fxq '.phpcs.xml.dist' <<<"$managed_paths_output"
grep -Fxq '.phpcs-security.xml.dist' <<<"$managed_paths_output"

missing_workflow_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$missing_workflow_fixture/"
mkdir -p "$missing_workflow_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$missing_workflow_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$missing_workflow_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
rm -f "$missing_workflow_fixture/.github/workflows/update-foundation.yml"
if WP_PLUGIN_BASE_ROOT="$missing_workflow_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Project validation unexpectedly passed with a missing managed workflow." >&2
  exit 1
fi

missing_managed_file_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$missing_managed_file_fixture/"
mkdir -p "$missing_managed_file_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$missing_managed_file_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$missing_managed_file_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
rm -f "$missing_managed_file_fixture/.github/dependabot.yml"
if WP_PLUGIN_BASE_ROOT="$missing_managed_file_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Project validation unexpectedly passed with a missing managed file." >&2
  exit 1
fi

missing_managed_file_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$missing_managed_file_fixture/"
mkdir -p "$missing_managed_file_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$missing_managed_file_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$missing_managed_file_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
rm -f "$missing_managed_file_fixture/.github/dependabot.yml"
mkdir -p "$missing_managed_file_fixture/.github/dependabot.yml"
if WP_PLUGIN_BASE_ROOT="$missing_managed_file_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Project validation unexpectedly passed with a managed file path replaced by a directory." >&2
  exit 1
fi

missing_managed_file_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$missing_managed_file_fixture/"
mkdir -p "$missing_managed_file_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$missing_managed_file_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$missing_managed_file_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
rm -f "$missing_managed_file_fixture/phpstan.neon.dist"
if WP_PLUGIN_BASE_ROOT="$missing_managed_file_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Project validation unexpectedly passed with a missing managed quality-pack file." >&2
  exit 1
fi

metadata_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$metadata_fixture/"
mkdir -p "$metadata_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$metadata_fixture/.wp-plugin-base/"
perl -0pi -e 's/^Tested up to: .*$//m' "$metadata_fixture/readme.txt"
WP_PLUGIN_BASE_ROOT="$metadata_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
if WP_PLUGIN_BASE_ROOT="$metadata_fixture" bash "$ROOT_DIR/scripts/ci/validate_wordpress_readiness.sh" "" "release/1.3.0" >/dev/null 2>&1; then
  echo "Readiness unexpectedly passed with invalid readme metadata." >&2
  exit 1
fi

deploy_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$deploy_fixture/"
mkdir -p "$deploy_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$deploy_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$deploy_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_ORG_DEPLOY_ENABLED=true
export WP_ORG_DEPLOY_ENABLED
if ! env -u GITHUB_ACTIONS -u GITHUB_REPOSITORY -u GH_TOKEN -u GITHUB_TOKEN \
  WP_PLUGIN_BASE_ROOT="$deploy_fixture" bash "$ROOT_DIR/scripts/ci/validate_wordpress_readiness.sh" "" "release/1.3.0" >/dev/null 2>&1; then
  echo "Readiness unexpectedly failed locally for a deploy-enabled project." >&2
  exit 1
fi
if GITHUB_ACTIONS=true GITHUB_REPOSITORY=example/repo WP_PLUGIN_BASE_ROOT="$deploy_fixture" bash "$ROOT_DIR/scripts/ci/validate_wordpress_readiness.sh" "" "release/1.3.0" >/dev/null 2>&1; then
  echo "Readiness unexpectedly passed in strict GitHub mode without deploy environment access." >&2
  exit 1
fi
unset WP_ORG_DEPLOY_ENABLED
rm -rf "$deploy_fixture"

deploy_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$deploy_fixture/"
mkdir -p "$deploy_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$deploy_fixture/.wp-plugin-base/"
mkdir -p "$deploy_fixture/docs"
mv "$deploy_fixture/readme.txt" "$deploy_fixture/docs/readme.txt"
perl -0pi -e 's/^README_FILE=.*/README_FILE=docs\/readme.txt/m' "$deploy_fixture/.wp-plugin-base.env"
WP_PLUGIN_BASE_ROOT="$deploy_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_ORG_DEPLOY_ENABLED=true
export WP_ORG_DEPLOY_ENABLED
if WP_PLUGIN_BASE_ROOT="$deploy_fixture" bash "$ROOT_DIR/scripts/ci/validate_wordpress_readiness.sh" "" "release/1.3.0" >/dev/null 2>&1; then
  echo "Readiness unexpectedly passed with an invalid WordPress.org deploy layout." >&2
  exit 1
fi
unset WP_ORG_DEPLOY_ENABLED

wp_build_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/wp-build-plugin/." "$wp_build_fixture/"
mkdir -p "$wp_build_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$wp_build_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$wp_build_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_PLUGIN_BASE_ROOT="$wp_build_fixture" bash "$ROOT_DIR/scripts/ci/validate_wordpress_readiness.sh" "" "release/1.4.0"
test -d "$wp_build_fixture/dist/package/build-ready-plugin/build"
test ! -e "$wp_build_fixture/dist/package/build-ready-plugin/packages"
test ! -e "$wp_build_fixture/dist/package/build-ready-plugin/routes"

cat >> "$wp_build_fixture/.wp-plugin-base.env" <<'EOF'
PACKAGE_INCLUDE=build-ready-plugin.php,readme.txt,package.json,build,packages/example/index.js,routes/example/index.js
EOF
WP_PLUGIN_BASE_ROOT="$wp_build_fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh" ""
package_zip="$(find "$wp_build_fixture/dist" -maxdepth 1 -name '*.zip' | head -n 1)"
test -n "$package_zip"
zip_listing="$(unzip -Z1 "$package_zip")"
grep -Fq 'build-ready-plugin/packages/example/index.js' <<<"$zip_listing"
grep -Fq 'build-ready-plugin/routes/example/index.js' <<<"$zip_listing"

pot_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/nonstandard-plugin/." "$pot_fixture/"
mkdir -p "$pot_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$pot_fixture/.wp-plugin-base/"
rm -f "$pot_fixture/languages/custom-plugin.pot"
test ! -e "$pot_fixture/languages/custom-plugin.pot"
WP_PLUGIN_BASE_ROOT="$pot_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_PLUGIN_BASE_ROOT="$pot_fixture" bash "$ROOT_DIR/scripts/release/generate_pot.sh"
test -f "$pot_fixture/languages/custom-plugin.pot"

echo "Validated full foundation repository at $ROOT_DIR"
