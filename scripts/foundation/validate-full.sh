#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "full foundation validation" git php node ruby perl rsync zip unzip jq docker

quality_fixture=""
metadata_fixture=""
deploy_fixture=""
wp_build_fixture=""
pot_fixture=""

cleanup() {
  rm -rf "$quality_fixture" "$metadata_fixture" "$deploy_fixture" "$wp_build_fixture" "$pot_fixture"
}

trap cleanup EXIT

bash "$ROOT_DIR/scripts/foundation/validate.sh"

quality_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$quality_fixture/"
mkdir -p "$quality_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$quality_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$quality_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_PLUGIN_BASE_ROOT="$quality_fixture" bash "$ROOT_DIR/scripts/ci/validate_wordpress_readiness.sh" "" "release/1.3.0"

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

pot_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/nonstandard-plugin/." "$pot_fixture/"
mkdir -p "$pot_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$pot_fixture/.wp-plugin-base/"
rm -f "$pot_fixture/languages/custom-plugin.pot"
WP_PLUGIN_BASE_ROOT="$pot_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_PLUGIN_BASE_ROOT="$pot_fixture" bash "$ROOT_DIR/scripts/release/generate_pot.sh"
test -f "$pot_fixture/languages/custom-plugin.pot"

echo "Validated full foundation repository at $ROOT_DIR"
