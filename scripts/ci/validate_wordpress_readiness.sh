#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

CONFIG_OVERRIDE="${1:-}"
BRANCH_NAME="${2:-${BRANCH_NAME:-}}"

wp_plugin_base_require_commands "WordPress readiness validation" git php node ruby perl rsync zip unzip jq docker
bash "$SCRIPT_DIR/validate_config.sh" --scope readiness "$CONFIG_OVERRIDE"

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

if [ -z "$BRANCH_NAME" ] && git -C "$ROOT_DIR" symbolic-ref --quiet --short HEAD >/dev/null 2>&1; then
  BRANCH_NAME="$(git -C "$ROOT_DIR" symbolic-ref --quiet --short HEAD)"
fi

bash "$SCRIPT_DIR/validate_project.sh" "$CONFIG_OVERRIDE" "$BRANCH_NAME"
bash "$SCRIPT_DIR/validate_wordpress_metadata.sh" "$CONFIG_OVERRIDE"
bash "$SCRIPT_DIR/run_plugin_check.sh" "$CONFIG_OVERRIDE"

if wp_plugin_base_is_true "$WORDPRESS_QUALITY_PACK_ENABLED"; then
  bash "$SCRIPT_DIR/run_quality_pack.sh" "$CONFIG_OVERRIDE"
fi

if wp_plugin_base_is_true "$WORDPRESS_SECURITY_PACK_ENABLED"; then
  bash "$SCRIPT_DIR/run_security_pack.sh" "$CONFIG_OVERRIDE"
fi

if wp_plugin_base_is_true "${WP_ORG_DEPLOY_ENABLED:-false}"; then
  deploy_env_check_args=()
  if wp_plugin_base_is_true "${WP_PLUGIN_BASE_STRICT_DEPLOY_ENV_PROTECTION:-false}"; then
    deploy_env_check_args+=(--strict)
  fi
  if [ -n "$CONFIG_OVERRIDE" ]; then
    deploy_env_check_args+=("$CONFIG_OVERRIDE")
  fi

  if [ "${#deploy_env_check_args[@]}" -gt 0 ]; then
    bash "$SCRIPT_DIR/check_deploy_environment_protection.sh" "${deploy_env_check_args[@]}"
  else
    bash "$SCRIPT_DIR/check_deploy_environment_protection.sh"
  fi
  version="$(wp_plugin_base_read_header_value "$(wp_plugin_base_resolve_path "$MAIN_PLUGIN_FILE")" 'Version')"
  bash "$SCRIPT_DIR/../release/validate_wordpress_org_deploy.sh" "$version" "$CONFIG_OVERRIDE" "$ROOT_DIR/dist/package/$PLUGIN_SLUG"
fi

echo "Validated WordPress readiness for $PLUGIN_SLUG."
