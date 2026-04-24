#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "package build" rsync zip

wp_plugin_base_load_config "${1:-}"
wp_plugin_base_require_vars PLUGIN_SLUG MAIN_PLUGIN_FILE ZIP_FILE

MAIN_PLUGIN_PATH="$(wp_plugin_base_resolve_path "$MAIN_PLUGIN_FILE")"
README_PATH="$(wp_plugin_base_resolve_path "$README_FILE")"
DISTIGNORE_PATH="$(wp_plugin_base_resolve_path "$DISTIGNORE_FILE")"
ACTIVE_CONFIG_RELATIVE_PATH="${CONFIG_PATH#"$ROOT_DIR"/}"
DIST_DIR="$ROOT_DIR/dist"
STAGE_ROOT="$DIST_DIR/package"
STAGE_DIR="$STAGE_ROOT/$PLUGIN_SLUG"
ZIP_PATH="$DIST_DIR/$ZIP_FILE"
EXCLUDES_FILE="$(mktemp)"

cleanup() {
  rm -f "$EXCLUDES_FILE"
}

trap cleanup EXIT

if [ ! -f "$MAIN_PLUGIN_PATH" ]; then
  echo "Main plugin file not found: $MAIN_PLUGIN_FILE" >&2
  exit 1
fi

if [[ ! "$ZIP_FILE" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.zip$ ]]; then
  echo "ZIP_FILE must be a simple zip filename: $ZIP_FILE" >&2
  exit 1
fi

wp_plugin_base_assert_path_within_root "$MAIN_PLUGIN_PATH" "Main plugin file"
wp_plugin_base_assert_path_within_root "$README_PATH" "Readme file"
wp_plugin_base_assert_path_within_root "$DISTIGNORE_PATH" "Distignore file"

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

  echo "Running build script: $BUILD_SCRIPT"
  (
    cd "$ROOT_DIR"
    bash "$BUILD_SCRIPT_PATH" ${build_script_args[@]+"${build_script_args[@]}"}
  )
  echo "Build script completed."
fi

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

rm -rf "$STAGE_ROOT" "$ZIP_PATH"
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

if wp_plugin_base_is_true "$runtime_update_enabled"; then
  staged_updater="$STAGE_DIR/lib/wp-plugin-base/wp-plugin-base-runtime-updater.php"
  staged_puc_entry="$STAGE_DIR/lib/wp-plugin-base/plugin-update-checker/plugin-update-checker.php"

  if [ ! -f "$staged_updater" ]; then
    echo "Build error: runtime updater support is enabled but $staged_updater is missing from the package." >&2
    echo "Run .wp-plugin-base/scripts/update/sync_child_repo.sh to install the runtime updater pack." >&2
    exit 1
  fi

  if [ ! -f "$staged_puc_entry" ]; then
    echo "Build error: runtime updater support is enabled but plugin-update-checker is missing from the package." >&2
    echo "Run .wp-plugin-base/scripts/update/sync_child_repo.sh to restore lib/wp-plugin-base/plugin-update-checker/." >&2
    exit 1
  fi
fi

(cd "$STAGE_ROOT" && zip -qr "$ZIP_PATH" "$PLUGIN_SLUG")

if [ ! -f "$ZIP_PATH" ]; then
  echo "Failed to create package zip." >&2
  exit 1
fi

if command -v unzip >/dev/null 2>&1; then
  zip_listing="$(unzip -Z1 "$ZIP_PATH")"
  if ! printf '%s\n' "$zip_listing" | grep -q "^$PLUGIN_SLUG/$MAIN_PLUGIN_FILE$"; then
    echo "Zip archive does not contain the expected plugin root structure." >&2
    exit 1
  fi
fi

echo "Created $ZIP_PATH"
