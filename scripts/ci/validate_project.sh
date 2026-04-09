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

wp_plugin_base_require_commands "project validation" git php node ruby perl rsync zip unzip
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

if [ -z "$BRANCH_NAME" ] && git -C "$ROOT_DIR" symbolic-ref --quiet --short HEAD >/dev/null 2>&1; then
  BRANCH_NAME="$(git -C "$ROOT_DIR" symbolic-ref --quiet --short HEAD)"
fi

bash "$SCRIPT_DIR/lint_php.sh" "$CONFIG_OVERRIDE"
bash "$SCRIPT_DIR/lint_js.sh" "$CONFIG_OVERRIDE"
bash "$SCRIPT_DIR/check_forbidden_files.sh" "$CONFIG_OVERRIDE"
bash "$SCRIPT_DIR/check_versions.sh" "" "$CONFIG_OVERRIDE"
bash "$SCRIPT_DIR/audit_workflows.sh" "$ROOT_DIR"

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

echo "Validated project repository at $ROOT_DIR"
