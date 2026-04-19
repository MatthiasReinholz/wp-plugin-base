#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

OUTPUT_SCOPE="${1:-project}"
CONFIG_OVERRIDE="${2:-}"
OUTPUT_PATH="${3:-${GITHUB_OUTPUT:-}}"

if [ -z "$OUTPUT_PATH" ]; then
  echo "Usage: $0 project|foundation [config-path] [output-path]" >&2
  exit 1
fi

case "$OUTPUT_SCOPE" in
  project)
    bash "$SCRIPT_DIR/validate_config.sh" --scope project "$CONFIG_OVERRIDE"
    ;;
  foundation)
    bash "$SCRIPT_DIR/validate_config.sh" --scope foundation "$CONFIG_OVERRIDE"
    ;;
  *)
    echo "Unsupported output scope: ${OUTPUT_SCOPE}" >&2
    exit 1
    ;;
esac

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

case "$OUTPUT_SCOPE" in
  project)
    {
      echo "automation_provider=${AUTOMATION_PROVIDER}"
      echo "automation_api_base=${AUTOMATION_API_BASE}"
      echo "trusted_git_hosts=${TRUSTED_GIT_HOSTS}"
      echo "plugin_slug=${PLUGIN_SLUG}"
      echo "plugin_name=${PLUGIN_NAME}"
      echo "zip_file=${ZIP_FILE}"
      echo "php_version=${PHP_VERSION}"
      echo "php_runtime_matrix=${PHP_RUNTIME_MATRIX}"
      echo "php_runtime_matrix_mode=${PHP_RUNTIME_MATRIX_MODE}"
      echo "node_version=${NODE_VERSION}"
      echo "wordpress_org_slug=${WORDPRESS_ORG_SLUG:-}"
      echo "wordpress_readiness_enabled=${WORDPRESS_READINESS_ENABLED}"
      echo "wordpress_quality_pack_enabled=${WORDPRESS_QUALITY_PACK_ENABLED}"
      echo "wordpress_security_pack_enabled=${WORDPRESS_SECURITY_PACK_ENABLED}"
      echo "woocommerce_com_product_id=${WOOCOMMERCE_COM_PRODUCT_ID}"
      echo "plugin_runtime_update_provider=${PLUGIN_RUNTIME_UPDATE_PROVIDER}"
      echo "plugin_runtime_update_source_url=${PLUGIN_RUNTIME_UPDATE_SOURCE_URL}"
      echo "github_release_updater_enabled=${GITHUB_RELEASE_UPDATER_ENABLED}"
      echo "github_release_updater_repo_url=${GITHUB_RELEASE_UPDATER_REPO_URL}"
      echo "build_script=${BUILD_SCRIPT}"
      echo "plugin_check_checks=${WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS}"
      echo "plugin_check_exclude_checks=${WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS}"
      echo "plugin_check_categories=${WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES}"
      echo "plugin_check_ignore_codes=${WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES}"
      echo "plugin_check_strict_warnings=${WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS}"
      echo "plugin_check_severity=${WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY}"
      echo "plugin_check_error_severity=${WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY}"
      echo "plugin_check_warning_severity=${WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY}"
      echo "simulate_release_workflow_enabled=${SIMULATE_RELEASE_WORKFLOW_ENABLED}"
      echo "glotpress_trigger_enabled=${GLOTPRESS_TRIGGER_ENABLED}"
      echo "glotpress_fail_on_error=${GLOTPRESS_FAIL_ON_ERROR}"
      echo "deploy_notification_enabled=${DEPLOY_NOTIFICATION_ENABLED}"
    } >> "$OUTPUT_PATH"
    ;;
  foundation)
    {
      echo "repository=${FOUNDATION_REPOSITORY}"
      echo "release_source_provider=${FOUNDATION_RELEASE_SOURCE_PROVIDER}"
      echo "release_source_reference=${FOUNDATION_RELEASE_SOURCE_REFERENCE}"
      echo "release_source_api_base=${FOUNDATION_RELEASE_SOURCE_API_BASE}"
      echo "release_source_sigstore_issuer=${FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER}"
      echo "version=${FOUNDATION_VERSION}"
    } >> "$OUTPUT_PATH"
    ;;
esac
