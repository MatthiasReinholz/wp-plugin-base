#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

CONFIG_OVERRIDE="${1:-}"
BRANCH_NAME="${2:-${BRANCH_NAME:-}}"

wp_plugin_base_require_commands "project validation" git php node ruby perl rsync zip unzip
bash "$SCRIPT_DIR/validate_config.sh" --scope project "$CONFIG_OVERRIDE"

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

required_managed_workflows=(
  ".github/workflows/ci.yml"
  ".github/workflows/prepare-release.yml"
  ".github/workflows/finalize-release.yml"
  ".github/workflows/release.yml"
  ".github/workflows/update-foundation.yml"
)

if wp_plugin_base_is_true "$WOOCOMMERCE_QIT_ENABLED"; then
  required_managed_workflows+=(".github/workflows/woocommerce-qit.yml")
fi

for required_workflow in "${required_managed_workflows[@]}"; do
  if [ ! -f "$ROOT_DIR/$required_workflow" ]; then
    echo "Managed workflow file is missing. Run .wp-plugin-base/scripts/update/sync_child_repo.sh: $required_workflow" >&2
    exit 1
  fi
done

if [ -z "$BRANCH_NAME" ] && git -C "$ROOT_DIR" symbolic-ref --quiet --short HEAD >/dev/null 2>&1; then
  BRANCH_NAME="$(git -C "$ROOT_DIR" symbolic-ref --quiet --short HEAD)"
fi

bash "$SCRIPT_DIR/lint_php.sh" "$CONFIG_OVERRIDE"
bash "$SCRIPT_DIR/lint_js.sh" "$CONFIG_OVERRIDE"
bash "$SCRIPT_DIR/check_forbidden_files.sh" "$CONFIG_OVERRIDE"
bash "$SCRIPT_DIR/check_versions.sh" "" "$CONFIG_OVERRIDE"
bash "$SCRIPT_DIR/audit_workflows.sh" "$ROOT_DIR"
bash "$SCRIPT_DIR/check_deploy_environment_protection.sh" --strict "$CONFIG_OVERRIDE"

if [ -n "$BRANCH_NAME" ]; then
  bash "$SCRIPT_DIR/check_release_branch.sh" "$BRANCH_NAME" "$CONFIG_OVERRIDE"
fi

bash "$SCRIPT_DIR/build_zip.sh" "$CONFIG_OVERRIDE"

echo "Validated project repository at $ROOT_DIR"
