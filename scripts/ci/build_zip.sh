#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"
# shellcheck source=../lib/managed_files.sh
. "$SCRIPT_DIR/../lib/managed_files.sh"
# shellcheck source=../lib/package_generation.sh
. "$SCRIPT_DIR/../lib/package_generation.sh"
# shellcheck source=../lib/build_outputs.sh
. "$SCRIPT_DIR/../lib/build_outputs.sh"

wp_plugin_base_require_commands "package build" rsync zip python3 ruby

wp_plugin_base_load_config "${1:-}"
wp_plugin_base_require_vars PLUGIN_SLUG MAIN_PLUGIN_FILE ZIP_FILE

MAIN_PLUGIN_PATH="$(wp_plugin_base_resolve_path "$MAIN_PLUGIN_FILE")"
README_PATH="$(wp_plugin_base_resolve_path "$README_FILE")"
DISTIGNORE_PATH="$(wp_plugin_base_resolve_path "$DISTIGNORE_FILE")"
ACTIVE_CONFIG_RELATIVE_PATH="${CONFIG_PATH#"$ROOT_DIR"/}"

if [ ! -f "$MAIN_PLUGIN_PATH" ]; then
  echo "Main plugin file not found: $MAIN_PLUGIN_FILE" >&2
  exit 1
fi

if [[ ! "$ZIP_FILE" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.zip$ ]]; then
  echo "ZIP_FILE must be a simple zip filename: $ZIP_FILE" >&2
  exit 1
fi

if [[ ! "$PLUGIN_SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "PLUGIN_SLUG must be a simple lowercase plugin slug: $PLUGIN_SLUG" >&2
  exit 1
fi

assert_package_output_paths() {
  python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" guard "$ROOT_DIR" "$PLUGIN_SLUG" "$ZIP_FILE"
}

# Reject unsafe output paths before executing a build or removing old artifacts.
assert_package_output_paths

wp_plugin_base_assert_path_within_root "$MAIN_PLUGIN_PATH" "Main plugin file"
wp_plugin_base_assert_path_within_root "$README_PATH" "Readme file"
wp_plugin_base_assert_path_within_root "$DISTIGNORE_PATH" "Distignore file"
wp_plugin_base_validate_build_inputs
if [ -n "${BUILD_SCRIPT:-}" ]; then
  wp_plugin_base_assert_path_within_root "$(wp_plugin_base_resolve_path "$BUILD_SCRIPT")" "BUILD_SCRIPT"
fi
wp_plugin_base_package_lock "$0" "$@"

GENERATION_DIR="$(python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" create "$ROOT_DIR" "$PLUGIN_SLUG" "$ZIP_FILE")"
STAGE_ROOT="$GENERATION_DIR/package"
STAGE_DIR="$STAGE_ROOT/$PLUGIN_SLUG"
ZIP_PATH="$GENERATION_DIR/$ZIP_FILE"
GENERATION_PUBLISHED=false
EXCLUDES_FILE="$(mktemp)"

cleanup() {
  rm -f "$EXCLUDES_FILE"
  if [ "$GENERATION_PUBLISHED" != true ]; then
    python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" discard "$ROOT_DIR" "$GENERATION_DIR" || true
  fi
}

trap cleanup EXIT


# Keep lib/ package-included: optional runtime packs (for example GitHub updater)
# ship files from lib/wp-plugin-base/ when explicitly enabled.
cat <<'EOF' > "$EXCLUDES_FILE"
/.git/
/.github/
/.gitlab/
/.gitea/
/.forgejo/
/.gitlab-ci.yml
/bitbucket-pipelines.yml
/.wp-plugin-base/
/.wordpress-org/
/dist/
/node_modules/
/.wp-plugin-base.env
/.wp-plugin-base-automation.json
/.wp-plugin-base-admin-ui/
EOF

if [ -f "$DISTIGNORE_PATH" ]; then
  cat "$DISTIGNORE_PATH" >> "$EXCLUDES_FILE"
fi

if [ -n "${BUILD_SCRIPT:-}" ]; then
  BUILD_SCRIPT_PATH="$(wp_plugin_base_resolve_path "$BUILD_SCRIPT")"
  if ! wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}" && [ "$BUILD_SCRIPT_PATH" = "$(wp_plugin_base_resolve_path ".wp-plugin-base-admin-ui/build.sh")" ]; then
    echo "ADMIN_UI_PACK_ENABLED=false but BUILD_SCRIPT still points to .wp-plugin-base-admin-ui/build.sh. Clear BUILD_SCRIPT or re-enable the admin UI pack before packaging." >&2
    exit 1
  fi
  wp_plugin_base_assert_path_within_root "$BUILD_SCRIPT_PATH" "BUILD_SCRIPT"
  if [ ! -f "$BUILD_SCRIPT_PATH" ]; then
    echo "Configured BUILD_SCRIPT was not found: $BUILD_SCRIPT" >&2
    exit 1
  fi

  build_script_args=()
  if [ -n "${BUILD_SCRIPT_ARGS:-}" ]; then
    while IFS= read -r arg; do
      [ -n "$arg" ] || continue
      build_script_args+=("$arg")
    done < <(wp_plugin_base_csv_to_lines "$BUILD_SCRIPT_ARGS")
  fi

  wp_plugin_base_prepare_build_outputs
  echo "Running build script: $BUILD_SCRIPT"
  (
    cd "$ROOT_DIR"
    bash "$BUILD_SCRIPT_PATH" ${build_script_args[@]+"${build_script_args[@]}"}
  )
  echo "Build script completed."
fi

wp_plugin_base_validate_build_outputs

if ! wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}" && [ -d "$ROOT_DIR/assets/admin-ui" ] && find "$ROOT_DIR/assets/admin-ui" -type f | grep -q .; then
  echo "ADMIN_UI_PACK_ENABLED=false but assets/admin-ui still contains built files after the configured build step. Remove the stale admin UI assets or re-enable the admin UI pack before packaging." >&2
  exit 1
fi

normalize_repo_relative_path() {
  local path="$1"
  path="${path#./}"
  path="${path#/}"
  printf '%s\n' "$path"
}

managed_exclude_path="/$(normalize_repo_relative_path "$WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE")"
printf '%s\n' "$managed_exclude_path" >> "$EXCLUDES_FILE"

if [ "$ACTIVE_CONFIG_RELATIVE_PATH" != "$CONFIG_PATH" ]; then
  active_config_exclude_path="/$(normalize_repo_relative_path "$ACTIVE_CONFIG_RELATIVE_PATH")"
  printf '%s\n' "$active_config_exclude_path" >> "$EXCLUDES_FILE"
fi

if [ -n "${PACKAGE_EXCLUDE:-}" ]; then
  while IFS= read -r exclude_path; do
    [ -n "$exclude_path" ] || continue
    printf '/%s\n' "$(normalize_repo_relative_path "$exclude_path")" >> "$EXCLUDES_FILE"
  done < <(wp_plugin_base_csv_to_lines "$PACKAGE_EXCLUDE")
fi

configured_readme_path="/$(normalize_repo_relative_path "$README_FILE")"
filtered_excludes_file="$(mktemp)"
grep -Fvx "$configured_readme_path" "$EXCLUDES_FILE" > "$filtered_excludes_file" || true
mv "$filtered_excludes_file" "$EXCLUDES_FILE"

# A project-owned build can change output paths, so recheck immediately before
# the first destructive operation as well as before running the build.
assert_package_output_paths
mkdir -p "$STAGE_DIR"

if [ -n "${PACKAGE_INCLUDE:-}" ]; then
  while IFS= read -r include_path; do
    source_path="$(wp_plugin_base_resolve_path "$include_path")"
    wp_plugin_base_assert_path_within_root "$source_path" "PACKAGE_INCLUDE"

    if [ ! -e "$source_path" ]; then
      echo "Missing package include path: $include_path" >&2
      exit 1
    fi

    include_path="${include_path#./}"
    include_path="${include_path#/}"

    (
      cd "$ROOT_DIR"
      rsync -a --relative --exclude-from="$EXCLUDES_FILE" "./$include_path" "$STAGE_DIR/"
    )
  done < <(wp_plugin_base_csv_to_lines "$PACKAGE_INCLUDE")
else
  rsync -a --exclude-from="$EXCLUDES_FILE" "$ROOT_DIR/" "$STAGE_DIR/"
fi

# The configured readme is a required package artifact. If exclusion rules dropped it
# (for example README_FILE under /docs), restore that single file explicitly.
if [ ! -f "$STAGE_DIR/$README_FILE" ] && [ -f "$README_PATH" ]; then
  mkdir -p "$(dirname "$STAGE_DIR/$README_FILE")"
  cp "$README_PATH" "$STAGE_DIR/$README_FILE"
fi

if [ ! -f "$STAGE_DIR/$MAIN_PLUGIN_FILE" ]; then
  echo "Package is missing the main plugin file: $MAIN_PLUGIN_FILE" >&2
  exit 1
fi

if [ ! -f "$STAGE_DIR/$README_FILE" ]; then
  echo "Package is missing the configured readme file: $README_FILE" >&2
  exit 1
fi

if [ -e "$STAGE_DIR/.wp-plugin-base" ] || [ -e "$STAGE_DIR/.github" ] || [ -e "$STAGE_DIR/.gitlab" ] || [ -e "$STAGE_DIR/.gitea" ] || [ -e "$STAGE_DIR/.forgejo" ] || [ -e "$STAGE_DIR/.gitlab-ci.yml" ] || [ -e "$STAGE_DIR/bitbucket-pipelines.yml" ] || [ -e "$STAGE_DIR/.wp-plugin-base.env" ]; then
  echo "Package contains foundation or CI-only files." >&2
  exit 1
fi

if [ "$ACTIVE_CONFIG_RELATIVE_PATH" != "$CONFIG_PATH" ] && [ -e "$STAGE_DIR/$ACTIVE_CONFIG_RELATIVE_PATH" ]; then
  echo "Package contains the active wp-plugin-base config file: $ACTIVE_CONFIG_RELATIVE_PATH" >&2
  exit 1
fi

if [ -e "$STAGE_DIR/$WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE" ]; then
  echo "Package contains the configured security suppressions file: $WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE" >&2
  exit 1
fi

normalized_readme_path="$(normalize_repo_relative_path "$README_FILE")"
allowed_docs_runtime_file=""
if [[ "$normalized_readme_path" == docs/* ]]; then
  allowed_docs_runtime_file="$normalized_readme_path"
fi

if [ -d "$STAGE_DIR/docs" ]; then
  while IFS= read -r docs_file; do
    [ -n "$docs_file" ] || continue
    relative_docs_file="${docs_file#"$STAGE_DIR/"}"
    if [ -n "$allowed_docs_runtime_file" ] && [ "$relative_docs_file" = "$allowed_docs_runtime_file" ]; then
      continue
    fi

    echo "Package contains development-only docs content: $relative_docs_file" >&2
    echo "Keep /docs out of distributable ZIPs (or move runtime-required content outside /docs)." >&2
    exit 1
  done < <(find "$STAGE_DIR/docs" -type f)
fi

runtime_update_enabled=false
if [ "${PLUGIN_RUNTIME_UPDATE_PROVIDER:-none}" != "none" ] || wp_plugin_base_is_true "${GITHUB_RELEASE_UPDATER_ENABLED:-false}"; then
  runtime_update_enabled=true
fi

assert_runtime_pack_php_is_packaged() {
  local pack_name="$1"
  local runtime_directory="$2"
  local seed_directory="${3:-}"
  local _template_file=""
  local relative_path=""
  local manifest=""
  local php_count=0

  # The managed manifest remains authoritative as classes are added or removed.
  manifest="$(wp_plugin_base_print_optional_managed_template_pairs "$pack_name" "$SCRIPT_DIR/../../templates/child")" || {
    echo "Cannot read the enabled runtime pack manifest: $pack_name" >&2
    exit 1
  }
  while IFS=$'\t' read -r _template_file relative_path; do
    case "$relative_path" in
      "$runtime_directory"/*.php)
        php_count=$((php_count + 1))
        if [ ! -f "$STAGE_DIR/$relative_path" ]; then
          echo "Enabled runtime pack is missing required PHP in the package: $relative_path" >&2
          exit 1
        fi
        ;;
    esac
  done <<< "$manifest"
  if [ "$php_count" -eq 0 ]; then
    echo "Enabled runtime pack has no authoritative PHP manifest: $pack_name" >&2
    exit 1
  fi

  if [ -n "$seed_directory" ] && [ ! -f "$STAGE_DIR/$seed_directory/bootstrap.php" ]; then
    echo "Enabled runtime pack is missing its child-owned bootstrap in the package: $seed_directory/bootstrap.php" >&2
    exit 1
  fi

}

if wp_plugin_base_is_true "$runtime_update_enabled"; then
  assert_runtime_pack_php_is_packaged "github-release-updater-pack" "lib/wp-plugin-base"
fi
if wp_plugin_base_is_true "${REST_OPERATIONS_PACK_ENABLED:-false}"; then
  assert_runtime_pack_php_is_packaged "rest-operations-pack" "lib/wp-plugin-base/rest-operations" "includes/rest-operations"
fi
if wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}"; then
  assert_runtime_pack_php_is_packaged "admin-ui-pack" "lib/wp-plugin-base/admin-ui" "includes/admin-ui"
fi

staged_symlinks="$(find "$STAGE_DIR" -type l -print)"
if [ -n "$staged_symlinks" ]; then
  echo "Package staging contains symlinks, which are not allowed in distributable ZIPs:" >&2
  printf '%s\n' "$staged_symlinks" | sed "s#^$STAGE_DIR/##" >&2
  exit 1
fi

wp_plugin_base_validate_build_outputs "$STAGE_DIR"
python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" normalize "$STAGE_DIR"
(
  # Info-ZIP honors implicit environment options even with explicit arguments.
  unset ZIPOPT ZIP UNZIP UNZIPOPT ZIPINFO ZIPINFOOPT
  export TZ=UTC
  cd "$STAGE_ROOT"
  find "$PLUGIN_SLUG" -print | LC_ALL=C sort | zip -X -q "$ZIP_PATH" -@
)
python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" verify "$ZIP_PATH" "$STAGE_DIR"
python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" publish "$ROOT_DIR" "$GENERATION_DIR" "$PLUGIN_SLUG" "$ZIP_FILE"
GENERATION_PUBLISHED=true

echo "Created verified package generation: $ZIP_PATH"
