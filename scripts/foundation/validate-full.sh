#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

ASSURANCE_MODE="${WP_PLUGIN_BASE_ASSURANCE_MODE:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      if [ "$#" -lt 2 ]; then
        echo "--mode requires a value." >&2
        exit 1
      fi
      ASSURANCE_MODE="$2"
      shift 2
      ;;
    --mode=*)
      ASSURANCE_MODE="${1#*=}"
      shift
      ;;
    *)
      echo "Usage: $0 [--mode fast-local|strict-local|ci]" >&2
      exit 1
      ;;
  esac
done

if [ -z "$ASSURANCE_MODE" ]; then
  if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    ASSURANCE_MODE="ci"
  elif [ "${WP_PLUGIN_BASE_STRICT_LINTERS:-false}" = "true" ]; then
    ASSURANCE_MODE="strict-local"
  else
    ASSURANCE_MODE="fast-local"
  fi
fi

wp_plugin_base_require_commands "full foundation validation" git php node ruby perl rsync zip unzip jq docker

quality_fixture=""
strict_plugin_check_fixture=""
security_pack_skip_fixture=""
custom_suppressions_fixture=""
custom_distignore_fixture=""
custom_config_fixture=""
missing_workflow_fixture=""
missing_managed_file_fixture=""
managed_directory_fixture=""
missing_pack_fixture=""
metadata_fixture=""
deploy_fixture=""
default_environment_fixture=""
absolute_include_fixture=""
invalid_distignore_fixture=""
wp_build_fixture=""
runtime_pack_fixture=""
runtime_pack_abilities_fixture=""
pot_fixture=""
yaml_workflow_fixture=""
custom_readme_fixture=""
docs_runtime_guard_fixture=""
release_features_fixture=""
phpdoc_fixture=""
simulate_fixture=""
glotpress_fixture=""

cleanup() {
  rm -rf "$quality_fixture" "$strict_plugin_check_fixture" "$security_pack_skip_fixture" "$custom_suppressions_fixture" "$custom_distignore_fixture" "$custom_config_fixture" "$missing_workflow_fixture" "$missing_managed_file_fixture" "$managed_directory_fixture" "$missing_pack_fixture" "$metadata_fixture" "$deploy_fixture" "$default_environment_fixture" "$absolute_include_fixture" "$invalid_distignore_fixture" "$wp_build_fixture" "$runtime_pack_fixture" "$runtime_pack_abilities_fixture" "$pot_fixture" "$yaml_workflow_fixture" "$custom_readme_fixture" "$docs_runtime_guard_fixture" "$release_features_fixture" "$phpdoc_fixture" "$simulate_fixture" "$glotpress_fixture"
}

trap cleanup EXIT

if [ "${WP_PLUGIN_BASE_SKIP_FAST_VALIDATE:-false}" != "true" ]; then
  bash "$ROOT_DIR/scripts/foundation/validate.sh" --mode "$ASSURANCE_MODE"
fi

quality_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$quality_fixture/"
mkdir -p "$quality_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$quality_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$quality_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_PLUGIN_BASE_ROOT="$quality_fixture" bash "$ROOT_DIR/scripts/ci/validate_wordpress_readiness.sh" "" "release/1.3.0"

default_environment_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$default_environment_fixture/"
mkdir -p "$default_environment_fixture/.wp-plugin-base"
perl -0pi -e 's/^PRODUCTION_ENVIRONMENT=.*\n//m' "$default_environment_fixture/.wp-plugin-base.env"
rsync -a --exclude '.git' "$ROOT_DIR/" "$default_environment_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$default_environment_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
grep -Fq 'environment: production' "$default_environment_fixture/.github/workflows/release.yml"

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
stage_paths_output="$(WP_PLUGIN_BASE_ROOT="$custom_suppressions_fixture" bash "$ROOT_DIR/scripts/ci/list_managed_files.sh" --mode stage ".wp-plugin-base.env")"
grep -Fxq '.security/custom-security-suppressions.json' <<<"$stage_paths_output"
if grep -Fxq '.security/custom-security-suppressions.json' <<<"$managed_paths_output"; then
  echo "Custom security suppressions should be staged but not listed as managed." >&2
  exit 1
fi
grep -Fxq '.phpcs.xml.dist' <<<"$managed_paths_output"
grep -Fxq '.phpcs-security.xml.dist' <<<"$managed_paths_output"
grep -Fq '/.security/custom-security-suppressions.json' "$custom_suppressions_fixture/.distignore"
grep -Fq '/.security/custom-security-suppressions.json export-ignore' "$custom_suppressions_fixture/.gitattributes"
WP_PLUGIN_BASE_ROOT="$custom_suppressions_fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh" ".wp-plugin-base.env"
custom_suppressions_zip="$(find "$custom_suppressions_fixture/dist" -maxdepth 1 -name '*.zip' | head -n 1)"
test -n "$custom_suppressions_zip"
custom_suppressions_listing="$(unzip -Z1 "$custom_suppressions_zip")"
if grep -Fq 'ready-blocks/.security/custom-security-suppressions.json' <<<"$custom_suppressions_listing"; then
  echo "Package unexpectedly included the configured custom suppressions file." >&2
  exit 1
fi

custom_distignore_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$custom_distignore_fixture/"
mkdir -p "$custom_distignore_fixture/.wp-plugin-base"
cat >> "$custom_distignore_fixture/.wp-plugin-base.env" <<'EOF'
DISTIGNORE_FILE=.config/custom.distignore
EOF
rsync -a --exclude '.git' "$ROOT_DIR/" "$custom_distignore_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$custom_distignore_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
test -f "$custom_distignore_fixture/.config/custom.distignore"
test ! -e "$custom_distignore_fixture/.distignore"
managed_paths_output="$(WP_PLUGIN_BASE_ROOT="$custom_distignore_fixture" bash "$ROOT_DIR/scripts/ci/list_managed_files.sh" ".wp-plugin-base.env")"
grep -Fxq '.config/custom.distignore' <<<"$managed_paths_output"
grep -Fq '/.config/custom.distignore' "$custom_distignore_fixture/.config/custom.distignore"
WP_PLUGIN_BASE_ROOT="$custom_distignore_fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh" ".wp-plugin-base.env"
custom_distignore_zip="$(find "$custom_distignore_fixture/dist" -maxdepth 1 -name '*.zip' | head -n 1)"
test -n "$custom_distignore_zip"
custom_distignore_listing="$(unzip -Z1 "$custom_distignore_zip")"
if grep -Fq 'ready-blocks/.config/custom.distignore' <<<"$custom_distignore_listing"; then
  echo "Package unexpectedly included the configured custom distignore file." >&2
  exit 1
fi
if grep -Fq 'ready-blocks/.distignore' <<<"$custom_distignore_listing"; then
  echo "Package unexpectedly included a stale default .distignore after switching DISTIGNORE_FILE." >&2
  exit 1
fi

custom_config_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$custom_config_fixture/"
mkdir -p "$custom_config_fixture/.wp-plugin-base" "$custom_config_fixture/.config"
mv "$custom_config_fixture/.wp-plugin-base.env" "$custom_config_fixture/.config/release.env"
rsync -a --exclude '.git' "$ROOT_DIR/" "$custom_config_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$custom_config_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh" ".config/release.env"
WP_PLUGIN_BASE_ROOT="$custom_config_fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh" ".config/release.env"
custom_config_zip="$(find "$custom_config_fixture/dist" -maxdepth 1 -name '*.zip' | head -n 1)"
test -n "$custom_config_zip"
custom_config_listing="$(unzip -Z1 "$custom_config_zip")"
if grep -Fq 'ready-blocks/.config/release.env' <<<"$custom_config_listing"; then
  echo "Package unexpectedly included the active custom wp-plugin-base config file." >&2
  exit 1
fi
cat >> "$custom_config_fixture/.config/release.env" <<'EOF'
PACKAGE_INCLUDE=ready-blocks.php,readme.txt,.config/release.env
EOF
WP_PLUGIN_BASE_ROOT="$custom_config_fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh" ".config/release.env"
custom_config_zip="$(find "$custom_config_fixture/dist" -maxdepth 1 -name '*.zip' | head -n 1)"
test -n "$custom_config_zip"
custom_config_listing="$(unzip -Z1 "$custom_config_zip")"
if grep -Fq 'ready-blocks/.config/release.env' <<<"$custom_config_listing"; then
  echo "Package include mode unexpectedly included the active custom wp-plugin-base config file." >&2
  exit 1
fi

yaml_workflow_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$yaml_workflow_fixture/"
mkdir -p "$yaml_workflow_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$yaml_workflow_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$yaml_workflow_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
cat > "$yaml_workflow_fixture/.github/workflows/custom.yaml" <<'EOF'
name: custom
on: workflow_dispatch
permissions:
  contents: read
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
EOF
if WP_PLUGIN_BASE_ROOT="$yaml_workflow_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Project validation unexpectedly passed with a .yaml workflow file." >&2
  exit 1
fi

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

managed_directory_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$managed_directory_fixture/"
mkdir -p "$managed_directory_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$managed_directory_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$managed_directory_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
rm -f "$managed_directory_fixture/.github/dependabot.yml"
mkdir -p "$managed_directory_fixture/.github/dependabot.yml"
if WP_PLUGIN_BASE_ROOT="$managed_directory_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Project validation unexpectedly passed with a managed file path replaced by a directory." >&2
  exit 1
fi

missing_pack_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$missing_pack_fixture/"
mkdir -p "$missing_pack_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$missing_pack_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$missing_pack_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
rm -f "$missing_pack_fixture/phpstan.neon.dist"
if WP_PLUGIN_BASE_ROOT="$missing_pack_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
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
test -f "$wp_build_fixture/dist/package/build-ready-plugin/build/generated/artifact.txt"
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

runtime_pack_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$runtime_pack_fixture/"
mkdir -p "$runtime_pack_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$runtime_pack_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$runtime_pack_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
grep -Fq 'settings.read' "$runtime_pack_fixture/includes/rest-operations/settings-operations.php"
test -f "$runtime_pack_fixture/.wp-plugin-base-admin-ui/package-lock.json"
if grep -Fq '@wordpress/dataviews' "$runtime_pack_fixture/.wp-plugin-base-admin-ui/package.json"; then
  echo "Default admin UI starter unexpectedly included the DataViews dependency surface." >&2
  exit 1
fi
printf '%s\n' '// child-owned-marker' >> "$runtime_pack_fixture/includes/rest-operations/settings-operations.php"
printf '%s\n' '// child-owned-marker' >> "$runtime_pack_fixture/.wp-plugin-base-admin-ui/src/app.js"
WP_PLUGIN_BASE_ROOT="$runtime_pack_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
grep -Fq 'child-owned-marker' "$runtime_pack_fixture/includes/rest-operations/settings-operations.php"
grep -Fq 'child-owned-marker' "$runtime_pack_fixture/.wp-plugin-base-admin-ui/src/app.js"
WP_PLUGIN_BASE_ROOT="$runtime_pack_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" ""
runtime_pack_zip="$(find "$runtime_pack_fixture/dist" -maxdepth 1 -name '*.zip' | head -n 1)"
test -n "$runtime_pack_zip"
runtime_pack_listing="$(unzip -Z1 "$runtime_pack_zip")"
grep -Fq 'runtime-pack-ready/assets/admin-ui/index.js' <<<"$runtime_pack_listing"
grep -Fq 'runtime-pack-ready/lib/wp-plugin-base/rest-operations/bootstrap.php' <<<"$runtime_pack_listing"
if grep -Fq 'runtime-pack-ready/.wp-plugin-base-admin-ui/' <<<"$runtime_pack_listing"; then
  echo "Runtime pack fixture unexpectedly shipped admin UI tooling sources." >&2
  exit 1
fi
perl -0pi -e 's/^ADMIN_UI_PACK_ENABLED=true$/ADMIN_UI_PACK_ENABLED=false/m' "$runtime_pack_fixture/.wp-plugin-base.env"
WP_PLUGIN_BASE_ROOT="$runtime_pack_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
if WP_PLUGIN_BASE_ROOT="$runtime_pack_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Runtime pack validation unexpectedly accepted an unreconciled admin UI disable transition." >&2
  exit 1
fi
perl -0pi -e "s~^[[:space:]]*require_once __DIR__ \\. '/lib/wp-plugin-base/admin-ui/bootstrap\\.php';\\n~~m" "$runtime_pack_fixture/runtime-pack-ready.php"
perl -0pi -e 's/^BUILD_SCRIPT=.*\n//m' "$runtime_pack_fixture/.wp-plugin-base.env"
rm -rf "$runtime_pack_fixture/assets/admin-ui"
WP_PLUGIN_BASE_ROOT="$runtime_pack_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" ""
runtime_pack_zip="$(find "$runtime_pack_fixture/dist" -maxdepth 1 -name '*.zip' | head -n 1)"
runtime_pack_listing="$(unzip -Z1 "$runtime_pack_zip")"
if grep -Fq 'runtime-pack-ready/.wp-plugin-base-admin-ui/' <<<"$runtime_pack_listing"; then
  echo "Runtime pack fixture shipped admin UI tooling after the pack was disabled." >&2
  exit 1
fi
if grep -Fq 'runtime-pack-ready/assets/admin-ui/' <<<"$runtime_pack_listing"; then
  echo "Runtime pack fixture shipped stale admin UI build outputs after the pack was disabled." >&2
  exit 1
fi

rm -rf "$runtime_pack_abilities_fixture"
runtime_pack_abilities_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$runtime_pack_abilities_fixture/"
mkdir -p "$runtime_pack_abilities_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$runtime_pack_abilities_fixture/.wp-plugin-base/"
cat >> "$runtime_pack_abilities_fixture/.wp-plugin-base.env" <<'EOF'
ADMIN_UI_STARTER=basic
ADMIN_UI_EXPERIMENTAL_DATAVIEWS=true
EOF
if WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/validate_config.sh" --scope project "" >/dev/null 2>&1; then
  echo "Config validation unexpectedly accepted conflicting admin starter inputs." >&2
  exit 1
fi

rm -rf "$runtime_pack_abilities_fixture"
runtime_pack_abilities_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$runtime_pack_abilities_fixture/"
mkdir -p "$runtime_pack_abilities_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$runtime_pack_abilities_fixture/.wp-plugin-base/"
cat >> "$runtime_pack_abilities_fixture/.wp-plugin-base.env" <<'EOF'
ADMIN_UI_STARTER=basic
EOF
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
perl -0pi -e 's/ADMIN_UI_STARTER=basic/ADMIN_UI_STARTER=dataviews/' "$runtime_pack_abilities_fixture/.wp-plugin-base.env"
if WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Runtime pack validation unexpectedly accepted an admin starter mismatch after the starter mode changed." >&2
  exit 1
fi

rm -rf "$runtime_pack_abilities_fixture"
runtime_pack_abilities_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$runtime_pack_abilities_fixture/"
mkdir -p "$runtime_pack_abilities_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$runtime_pack_abilities_fixture/.wp-plugin-base/"
cat >> "$runtime_pack_abilities_fixture/.wp-plugin-base.env" <<'EOF'
ADMIN_UI_STARTER=dataviews
EOF
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
grep -Fq '@wordpress/dataviews' "$runtime_pack_abilities_fixture/.wp-plugin-base-admin-ui/package.json"
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" ""
bash "$ROOT_DIR/scripts/foundation/test_wordpress_env_retry.sh"
bash "$ROOT_DIR/scripts/foundation/test_runtime_packs_wordpress.sh"

rm -rf "$runtime_pack_abilities_fixture"
runtime_pack_abilities_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$runtime_pack_abilities_fixture/"
mkdir -p "$runtime_pack_abilities_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$runtime_pack_abilities_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
perl -0pi -e "s/'callback'\\s*=>\\s*'wp_plugin_base_example_rest_operation_get_settings'/'callback'        => 'this_callback_does_not_exist'/" "$runtime_pack_abilities_fixture/includes/rest-operations/settings-operations.php"
if WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Runtime pack validation unexpectedly passed with a non-callable operation callback." >&2
  exit 1
fi

rm -rf "$runtime_pack_abilities_fixture"
runtime_pack_abilities_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$runtime_pack_abilities_fixture/"
mkdir -p "$runtime_pack_abilities_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$runtime_pack_abilities_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
perl -0pi -e "s/'capability'\\s*=>\\s*'manage_options',\\n//" "$runtime_pack_abilities_fixture/includes/rest-operations/settings-operations.php"
if WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Runtime pack validation unexpectedly passed with a non-public operation missing a capability declaration." >&2
  exit 1
fi

rm -rf "$runtime_pack_abilities_fixture"
runtime_pack_abilities_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$runtime_pack_abilities_fixture/"
mkdir -p "$runtime_pack_abilities_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$runtime_pack_abilities_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
perl -0pi -e "s/'id'\\s*=>\\s*'example-items\\.list'/'id'              => 'settings.read'/" "$runtime_pack_abilities_fixture/includes/rest-operations/example-items-operations.php"
if WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Runtime pack validation unexpectedly passed with duplicate operation ids." >&2
  exit 1
fi

rm -rf "$runtime_pack_abilities_fixture"
runtime_pack_abilities_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$runtime_pack_abilities_fixture/"
mkdir -p "$runtime_pack_abilities_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$runtime_pack_abilities_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
perl -0pi -e "s|'route'\\s*=>\\s*'/example-items'|'route'           => '/settings'|" "$runtime_pack_abilities_fixture/includes/rest-operations/example-items-operations.php"
if WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Runtime pack validation unexpectedly passed with duplicate route+method entries." >&2
  exit 1
fi

rm -rf "$runtime_pack_abilities_fixture"
runtime_pack_abilities_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$runtime_pack_abilities_fixture/"
mkdir -p "$runtime_pack_abilities_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$runtime_pack_abilities_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
perl -0pi -e "s/'visibility'\\s*=>\\s*'admin'/'visibility'      => 'public'/" "$runtime_pack_abilities_fixture/includes/rest-operations/settings-operations.php"
if WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Runtime pack validation unexpectedly passed with a public operation missing suppression." >&2
  exit 1
fi
cat > "$runtime_pack_abilities_fixture/.wp-plugin-base-security-suppressions.json" <<'EOF'
{
  "suppressions": [
    {
      "kind": "rest_public_operation",
      "identifier": "settings.read",
      "path": "includes/rest-operations/settings-operations.php"
    }
  ]
}
EOF
if WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/scan_rest_operation_contract.sh" "" >/dev/null 2>&1; then
  echo "REST operation contract unexpectedly passed with a malformed public-operation suppression." >&2
  exit 1
fi
cat > "$runtime_pack_abilities_fixture/.wp-plugin-base-security-suppressions.json" <<'EOF'
{
  "suppressions": [
    {
      "kind": "rest_public_operation",
      "identifier": "settings.read",
      "path": "includes/rest-operations/settings-operations.php",
      "justification": "   "
    }
  ]
}
EOF
if WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/scan_rest_operation_contract.sh" "" >/dev/null 2>&1; then
  echo "REST operation contract unexpectedly passed with a blank public-operation suppression justification." >&2
  exit 1
fi
cat > "$runtime_pack_abilities_fixture/.wp-plugin-base-security-suppressions.json" <<'EOF'
{
  "suppressions": [
    {
      "kind": "rest_public_operation",
      "identifier": "settings.read",
      "path": "includes/rest-operations/settings-operations.php",
      "justification": "Settings reads are intentionally public for this fixture and return non-sensitive demo data only."
    }
  ]
}
EOF
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/scan_rest_operation_contract.sh" ""

rm -rf "$runtime_pack_abilities_fixture"
runtime_pack_abilities_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$runtime_pack_abilities_fixture/"
mkdir -p "$runtime_pack_abilities_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$runtime_pack_abilities_fixture/.wp-plugin-base/"
cat > "$runtime_pack_abilities_fixture/includes/legacy-rest.php" <<'EOF'
<?php

if ( ! defined( 'ABSPATH' ) ) {
  exit;
}

register_rest_route(
  'runtime-pack-ready/v1',
  '/legacy',
  array(
    'methods'             => 'GET',
    'callback'            => '__return_null',
    'permission_callback' => '__return_false',
  )
);
EOF
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
if WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Runtime pack validation unexpectedly passed with an unsuppressed legacy register_rest_route call." >&2
  exit 1
fi
cat > "$runtime_pack_abilities_fixture/.wp-plugin-base-security-suppressions.json" <<'EOF'
{
  "suppressions": [
    {
      "kind": "rest_route_bypass",
      "identifier": "register_rest_route",
      "path": "includes/legacy-rest.php",
      "justification": "Temporary migration bridge while a legacy endpoint moves into the managed operation registry."
    }
  ]
}
EOF
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" ""

rm -rf "$runtime_pack_abilities_fixture"
runtime_pack_abilities_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$runtime_pack_abilities_fixture/"
mkdir -p "$runtime_pack_abilities_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$runtime_pack_abilities_fixture/.wp-plugin-base/"
mkdir -p "$runtime_pack_abilities_fixture/lib"
cat > "$runtime_pack_abilities_fixture/lib/custom-rest.php" <<'EOF'
<?php

if ( ! defined( 'ABSPATH' ) ) {
  exit;
}

register_rest_route(
  'runtime-pack-ready/v1',
  '/custom-lib',
  array(
    'methods'             => 'GET',
    'callback'            => '__return_null',
    'permission_callback' => '__return_false',
  )
);
EOF
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
if WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" >/dev/null 2>&1; then
  echo "Runtime pack validation unexpectedly passed with an unsuppressed child lib/register_rest_route call." >&2
  exit 1
fi
cat > "$runtime_pack_abilities_fixture/.wp-plugin-base-security-suppressions.json" <<'EOF'
{
  "suppressions": [
    {
      "kind": "rest_route_bypass",
      "identifier": "register_rest_route",
      "path": "lib/custom-rest.php",
      "justification": "Temporary migration bridge while a child lib endpoint moves into the managed operation registry."
    }
  ]
}
EOF
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" ""

rm -rf "$runtime_pack_abilities_fixture"
runtime_pack_abilities_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$runtime_pack_abilities_fixture/"
mkdir -p "$runtime_pack_abilities_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$runtime_pack_abilities_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
cat > "$runtime_pack_abilities_fixture/includes/comment-only.php" <<'EOF'
<?php
// register_rest_route( 'runtime-pack-ready/v1', '/comment-only', array() );
EOF
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/scan_rest_operation_contract.sh" ""

rm -rf "$runtime_pack_abilities_fixture"
runtime_pack_abilities_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$runtime_pack_abilities_fixture/"
mkdir -p "$runtime_pack_abilities_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$runtime_pack_abilities_fixture/.wp-plugin-base/"
cat >> "$runtime_pack_abilities_fixture/.wp-plugin-base.env" <<'EOF'
WORDPRESS_QUALITY_PACK_ENABLED=false
WORDPRESS_SECURITY_PACK_ENABLED=false
EOF
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
mkdir -p "$runtime_pack_abilities_fixture/.wp-plugin-base-quality-pack/vendor/example"
cat > "$runtime_pack_abilities_fixture/.wp-plugin-base-quality-pack/vendor/example/legacy-rest.php" <<'EOF'
<?php

register_rest_route(
  'runtime-pack-ready/v1',
  '/pack-fixture',
  array(
    'methods'             => 'GET',
    'callback'            => '__return_null',
    'permission_callback' => '__return_false',
  )
);
EOF
WP_PLUGIN_BASE_ROOT="$runtime_pack_abilities_fixture" bash "$ROOT_DIR/scripts/ci/scan_rest_operation_contract.sh" ""

release_features_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/wp-build-plugin/." "$release_features_fixture/"
mkdir -p "$release_features_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$release_features_fixture/.wp-plugin-base/"
cat > "$release_features_fixture/package-lock.json" <<'EOF'
{
  "name": "build-ready-plugin",
  "version": "1.0.0",
  "packages": {
    "": {
      "name": "build-ready-plugin",
      "version": "1.0.0"
    }
  }
}
EOF
cat > "$release_features_fixture/CHANGELOG.md" <<'EOF'
# Changelog

## v1.0.0

* Initial release.
EOF
cat >> "$release_features_fixture/.wp-plugin-base.env" <<'EOF'
CHANGELOG_MD_SYNC_ENABLED=true
EOF
WP_PLUGIN_BASE_ROOT="$release_features_fixture" bash "$ROOT_DIR/scripts/release/bump_version.sh" "1.0.1"
WP_PLUGIN_BASE_ROOT="$release_features_fixture" bash "$ROOT_DIR/scripts/ci/check_versions.sh" "1.0.1"
grep -Fq '"version": "1.0.1"' "$release_features_fixture/package.json"
grep -Fq '"version": "1.0.1"' "$release_features_fixture/package-lock.json"
grep -Fq '## v1.0.1' "$release_features_fixture/CHANGELOG.md"
if [ "$(grep -c '^## v1\.0\.1$' "$release_features_fixture/CHANGELOG.md")" -ne 1 ]; then
  echo "CHANGELOG.md sync inserted duplicate version headings." >&2
  exit 1
fi

phpdoc_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$phpdoc_fixture/"
mkdir -p "$phpdoc_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$phpdoc_fixture/.wp-plugin-base/"
cat > "$phpdoc_fixture/includes/phpdoc.php" <<'EOF'
<?php
/**
 * Example
 *
 * @since NEXT
 * @version NEXT
 */
EOF
cat >> "$phpdoc_fixture/.wp-plugin-base.env" <<'EOF'
PHPDOC_VERSION_REPLACEMENT_ENABLED=true
PHPDOC_VERSION_PLACEHOLDER=NEXT
EOF
WP_PLUGIN_BASE_ROOT="$phpdoc_fixture" bash "$ROOT_DIR/scripts/release/bump_version.sh" "1.2.3"
grep -Fq '@since 1.2.3' "$phpdoc_fixture/includes/phpdoc.php"
grep -Fq '@version 1.2.3' "$phpdoc_fixture/includes/phpdoc.php"

simulate_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$simulate_fixture/"
mkdir -p "$simulate_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$simulate_fixture/.wp-plugin-base/"
(
  cd "$simulate_fixture"
  git init -q
  git config user.email "tests@example.com"
  git config user.name "Test Runner"
  git add .
  git commit -qm "baseline"
)
simulate_output="$(
  WP_PLUGIN_BASE_ROOT="$simulate_fixture" bash "$ROOT_DIR/scripts/release/simulate_release.sh" patch ".wp-plugin-base.env"
)"
grep -Fq '=== Release Simulation ===' <<<"$simulate_output"
if [ -n "$(git -C "$simulate_fixture" status --porcelain --untracked-files=no)" ]; then
  echo "Release simulation unexpectedly changed the working tree." >&2
  exit 1
fi

glotpress_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$glotpress_fixture/"
mkdir -p "$glotpress_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$glotpress_fixture/.wp-plugin-base/"
cat >> "$glotpress_fixture/.wp-plugin-base.env" <<'EOF'
GLOTPRESS_TRIGGER_ENABLED=true
GLOTPRESS_URL=http://insecure.example.test
GLOTPRESS_PROJECT_SLUG=example
EOF
if WP_PLUGIN_BASE_ROOT="$glotpress_fixture" bash "$ROOT_DIR/scripts/ci/validate_config.sh" "" >/dev/null 2>&1; then
  echo "Config validation unexpectedly accepted an insecure GLOTPRESS_URL." >&2
  exit 1
fi

absolute_include_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$absolute_include_fixture/"
mkdir -p "$absolute_include_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$absolute_include_fixture/.wp-plugin-base/"
cat >> "$absolute_include_fixture/.wp-plugin-base.env" <<EOF
PACKAGE_INCLUDE=$absolute_include_fixture/includes
EOF
if WP_PLUGIN_BASE_ROOT="$absolute_include_fixture" bash "$ROOT_DIR/scripts/ci/validate_config.sh" "" >/dev/null 2>&1; then
  echo "Config validation unexpectedly accepted an absolute PACKAGE_INCLUDE path." >&2
  exit 1
fi

invalid_distignore_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$invalid_distignore_fixture/"
mkdir -p "$invalid_distignore_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$invalid_distignore_fixture/.wp-plugin-base/"
cat >> "$invalid_distignore_fixture/.wp-plugin-base.env" <<'EOF'
DISTIGNORE_FILE=.wp-plugin-base.env
EOF
if WP_PLUGIN_BASE_ROOT="$invalid_distignore_fixture" bash "$ROOT_DIR/scripts/ci/validate_config.sh" "" >/dev/null 2>&1; then
  echo "Config validation unexpectedly accepted a non-distignore DISTIGNORE_FILE target." >&2
  exit 1
fi

custom_readme_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$custom_readme_fixture/"
mkdir -p "$custom_readme_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$custom_readme_fixture/.wp-plugin-base/"
mv "$custom_readme_fixture/readme.txt" "$custom_readme_fixture/README.md"
perl -0pi -e 's/^README_FILE=.*/README_FILE=README.md/m' "$custom_readme_fixture/.wp-plugin-base.env"
WP_PLUGIN_BASE_ROOT="$custom_readme_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_PLUGIN_BASE_ROOT="$custom_readme_fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh" ""
custom_readme_zip="$(find "$custom_readme_fixture/dist" -maxdepth 1 -name '*.zip' | head -n 1)"
test -n "$custom_readme_zip"
custom_readme_listing="$(unzip -Z1 "$custom_readme_zip")"
grep -Fq 'standard-plugin/README.md' <<<"$custom_readme_listing"

docs_runtime_guard_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$docs_runtime_guard_fixture/"
mkdir -p "$docs_runtime_guard_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$docs_runtime_guard_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$docs_runtime_guard_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
mkdir -p "$docs_runtime_guard_fixture/docs"
cat > "$docs_runtime_guard_fixture/docs/dev-notes.md" <<'EOF_DOCS'
# Development Notes
EOF_DOCS
perl -0pi -e 's#^/docs\n##m' "$docs_runtime_guard_fixture/.distignore"

if WP_PLUGIN_BASE_ROOT="$docs_runtime_guard_fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh" "" >/dev/null 2>&1; then
  echo "Package build unexpectedly accepted /docs runtime content after removing docs exclusion." >&2
  exit 1
fi

pot_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/nonstandard-plugin/." "$pot_fixture/"
mkdir -p "$pot_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$pot_fixture/.wp-plugin-base/"
rm -f "$pot_fixture/languages/custom-plugin.pot"
test ! -e "$pot_fixture/languages/custom-plugin.pot"
WP_PLUGIN_BASE_ROOT="$pot_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_PLUGIN_BASE_ROOT="$pot_fixture" bash "$ROOT_DIR/scripts/release/generate_pot.sh"
test -f "$pot_fixture/languages/custom-plugin.pot"

echo "Validated full foundation repository at $ROOT_DIR ($ASSURANCE_MODE)"
