#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/managed_files.sh
. "$SCRIPT_DIR/../lib/managed_files.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

CONFIG_OVERRIDE="${1:-}"
BRANCH_NAME="${2:-${BRANCH_NAME:-}}"

wp_plugin_base_require_commands "project validation" git php node ruby perl rsync zip unzip jq
bash "$SCRIPT_DIR/validate_config.sh" --scope project "$CONFIG_OVERRIDE"

wp_plugin_base_load_config "$CONFIG_OVERRIDE"
while IFS= read -r required_path; do
  [ -n "$required_path" ] || continue
  resolved_required_path="$(wp_plugin_base_resolve_path "$required_path")"
  if [ ! -f "$resolved_required_path" ]; then
    echo "Managed file is missing or not a regular file. Run .wp-plugin-base/scripts/update/sync_child_repo.sh: $required_path" >&2
    exit 1
  fi
done < <(wp_plugin_base_print_managed_paths)

while IFS= read -r required_path; do
  [ -n "$required_path" ] || continue
  resolved_required_path="$(wp_plugin_base_resolve_path "$required_path")"
  if [ ! -f "$resolved_required_path" ]; then
    echo "Required seeded pack file is missing or not a regular file. Run .wp-plugin-base/scripts/update/sync_child_repo.sh: $required_path" >&2
    exit 1
  fi
done < <(wp_plugin_base_print_required_seed_paths)

if wp_plugin_base_is_true "${GITHUB_RELEASE_UPDATER_ENABLED:-false}"; then
  main_plugin_path="$(wp_plugin_base_resolve_path "$MAIN_PLUGIN_FILE")"
  updater_include_regex='^[[:space:]]*require_once[[:space:]]+__DIR__[[:space:]]*\.[[:space:]]*['\''"]/lib/wp-plugin-base/wp-plugin-base-github-updater\.php['\''"][[:space:]]*;'

  if ! grep -Eq "$updater_include_regex" "$main_plugin_path"; then
    echo "GITHUB_RELEASE_UPDATER_ENABLED=true requires the main plugin file to include:" >&2
    echo "require_once __DIR__ . '/lib/wp-plugin-base/wp-plugin-base-github-updater.php';" >&2
    exit 1
  fi
fi

main_plugin_path="$(wp_plugin_base_resolve_path "$MAIN_PLUGIN_FILE")"
rest_pack_include_regex='^[[:space:]]*require_once[[:space:]]+__DIR__[[:space:]]*\.[[:space:]]*['\''"]/lib/wp-plugin-base/rest-operations/bootstrap\.php['\''"][[:space:]]*;'
admin_ui_pack_include_regex='^[[:space:]]*require_once[[:space:]]+__DIR__[[:space:]]*\.[[:space:]]*['\''"]/lib/wp-plugin-base/admin-ui/bootstrap\.php['\''"][[:space:]]*;'

if wp_plugin_base_is_true "${REST_OPERATIONS_PACK_ENABLED:-false}"; then
  if ! grep -Eq "$rest_pack_include_regex" "$main_plugin_path"; then
    echo "REST_OPERATIONS_PACK_ENABLED=true requires the main plugin file to include:" >&2
    echo "require_once __DIR__ . '/lib/wp-plugin-base/rest-operations/bootstrap.php';" >&2
    exit 1
  fi
elif grep -Eq "$rest_pack_include_regex" "$main_plugin_path"; then
  echo "REST_OPERATIONS_PACK_ENABLED=false but the main plugin file still includes lib/wp-plugin-base/rest-operations/bootstrap.php. Remove the child-owned include or re-enable the pack." >&2
  exit 1
fi

if wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}"; then
  admin_ui_package_path="$(wp_plugin_base_resolve_path ".wp-plugin-base-admin-ui/package.json")"

  if ! grep -Eq "$admin_ui_pack_include_regex" "$main_plugin_path"; then
    echo "ADMIN_UI_PACK_ENABLED=true requires the main plugin file to include:" >&2
    echo "require_once __DIR__ . '/lib/wp-plugin-base/admin-ui/bootstrap.php';" >&2
    exit 1
  fi

  if [ ! -f "$admin_ui_package_path" ]; then
    echo "ADMIN_UI_PACK_ENABLED=true requires .wp-plugin-base-admin-ui/package.json to exist. Run .wp-plugin-base/scripts/update/sync_child_repo.sh." >&2
    exit 1
  fi

  admin_ui_has_dataviews="$(
    jq -r '
      (
        (.dependencies // {}) + (.devDependencies // {})
      )
      | has("@wordpress/dataviews")
    ' "$admin_ui_package_path"
  )"

  if [ "${ADMIN_UI_STARTER:-basic}" = "dataviews" ] && [ "$admin_ui_has_dataviews" != "true" ]; then
    echo "ADMIN_UI_STARTER=dataviews is configured, but .wp-plugin-base-admin-ui/package.json does not include @wordpress/dataviews. The child-owned starter files still match the basic starter. Reconcile the starter manually or re-seed the admin UI starter." >&2
    exit 1
  fi

  if [ "${ADMIN_UI_STARTER:-basic}" = "basic" ] && [ "$admin_ui_has_dataviews" = "true" ]; then
    echo "ADMIN_UI_STARTER=basic is configured, but .wp-plugin-base-admin-ui/package.json still includes @wordpress/dataviews. The child-owned starter files still match the dataviews starter. Reconcile the starter manually or re-seed the admin UI starter." >&2
    exit 1
  fi
else
  if grep -Eq "$admin_ui_pack_include_regex" "$main_plugin_path"; then
    echo "ADMIN_UI_PACK_ENABLED=false but the main plugin file still includes lib/wp-plugin-base/admin-ui/bootstrap.php. Remove the child-owned include or re-enable the pack." >&2
    exit 1
  fi

  if [ -n "${BUILD_SCRIPT:-}" ]; then
    build_script_path="$(wp_plugin_base_resolve_path "$BUILD_SCRIPT")"
    admin_ui_build_script_path="$(wp_plugin_base_resolve_path ".wp-plugin-base-admin-ui/build.sh")"

    if [ "$build_script_path" = "$admin_ui_build_script_path" ]; then
      echo "ADMIN_UI_PACK_ENABLED=false but BUILD_SCRIPT still points to .wp-plugin-base-admin-ui/build.sh. Clear BUILD_SCRIPT or re-enable the admin UI pack before validation or packaging." >&2
      exit 1
    fi
  fi

  if [ -d "$ROOT_DIR/assets/admin-ui" ] && find "$ROOT_DIR/assets/admin-ui" -type f | grep -q .; then
    echo "ADMIN_UI_PACK_ENABLED=false but assets/admin-ui still contains built files. Remove the stale admin UI build outputs before packaging." >&2
    exit 1
  fi
fi

if [ -z "$BRANCH_NAME" ] && git -C "$ROOT_DIR" symbolic-ref --quiet --short HEAD >/dev/null 2>&1; then
  BRANCH_NAME="$(git -C "$ROOT_DIR" symbolic-ref --quiet --short HEAD)"
fi

bash "$SCRIPT_DIR/lint_php.sh" "$CONFIG_OVERRIDE"
bash "$SCRIPT_DIR/lint_js.sh" "$CONFIG_OVERRIDE"
bash "$SCRIPT_DIR/check_forbidden_files.sh" "$CONFIG_OVERRIDE"
bash "$SCRIPT_DIR/check_versions.sh" "" "$CONFIG_OVERRIDE"
bash "$SCRIPT_DIR/audit_workflows.sh" "$ROOT_DIR"

if wp_plugin_base_is_true "${REST_OPERATIONS_PACK_ENABLED:-false}"; then
  bash "$SCRIPT_DIR/scan_rest_operation_contract.sh" "$CONFIG_OVERRIDE"
fi

deploy_protection_args=()
if wp_plugin_base_is_true "${WP_PLUGIN_BASE_STRICT_DEPLOY_ENV_PROTECTION:-false}" || [ -n "${GITHUB_ACTIONS:-}" ]; then
  deploy_protection_args+=(--strict)
fi
if [ "${#deploy_protection_args[@]}" -gt 0 ]; then
  bash "$SCRIPT_DIR/check_deploy_environment_protection.sh" "${deploy_protection_args[@]}" "$CONFIG_OVERRIDE"
else
  bash "$SCRIPT_DIR/check_deploy_environment_protection.sh" "$CONFIG_OVERRIDE"
fi

if [ -n "$BRANCH_NAME" ]; then
  bash "$SCRIPT_DIR/check_release_branch.sh" "$BRANCH_NAME" "$CONFIG_OVERRIDE"
fi

bash "$SCRIPT_DIR/build_zip.sh" "$CONFIG_OVERRIDE"

if wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}"; then
  bash "$SCRIPT_DIR/check_admin_ui_pack.sh" "$CONFIG_OVERRIDE"
fi

echo "Validated project repository at $ROOT_DIR"
