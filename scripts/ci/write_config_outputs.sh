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
    } >> "$OUTPUT_PATH"
    ;;
  foundation)
    {
      echo "repository=${FOUNDATION_REPOSITORY}"
      echo "version=${FOUNDATION_VERSION}"
    } >> "$OUTPUT_PATH"
    ;;
esac
