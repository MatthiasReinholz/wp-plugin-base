#!/usr/bin/env bash
# Source after load_config.sh. Each managed consumer captures one result file.
WP_PLUGIN_BASE_PACKAGE_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_generation.py"

wp_plugin_base_package_lock() {
  python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" guard "$ROOT_DIR" "$PLUGIN_SLUG" "$ZIP_FILE"
  if ! python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" held "$ROOT_DIR"; then
    exec python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" lock "$ROOT_DIR" bash "$@"
  fi
}

wp_plugin_base_capture_package() {
  local result_file="$1" key value validated
  unset WP_PLUGIN_BASE_PACKAGE_DIR WP_PLUGIN_BASE_PACKAGE_ZIP WP_PLUGIN_BASE_PACKAGE_SBOM \
    WP_PLUGIN_BASE_PACKAGE_SIGNATURE WP_PLUGIN_BASE_PACKAGE_DESCRIPTOR WP_PLUGIN_BASE_PACKAGE_SHA256
  validated="$(python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" validate-result "$result_file")" || return 1
  while IFS='=' read -r key value; do
    case "$key" in
      package_dir) export WP_PLUGIN_BASE_PACKAGE_DIR="$value" ;;
      zip_path) export WP_PLUGIN_BASE_PACKAGE_ZIP="$value" ;;
      sbom_path) export WP_PLUGIN_BASE_PACKAGE_SBOM="$value" ;;
      signature_path) export WP_PLUGIN_BASE_PACKAGE_SIGNATURE="$value" ;;
      descriptor_path) export WP_PLUGIN_BASE_PACKAGE_DESCRIPTOR="$value" ;;
      sha256) export WP_PLUGIN_BASE_PACKAGE_SHA256="$value" ;;
      *) echo "Unexpected package result field: $key" >&2; return 1 ;;
    esac
  done <<< "$validated"
  if [ -z "${WP_PLUGIN_BASE_PACKAGE_DESCRIPTOR:-}" ]; then
    echo "Package generation result is missing." >&2
    return 1
  fi
  python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" check "$WP_PLUGIN_BASE_PACKAGE_DESCRIPTOR"
}

wp_plugin_base_check_captured_package() {
  if [ -n "${WP_PLUGIN_BASE_PACKAGE_DESCRIPTOR:-}" ]; then
    python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" check "$WP_PLUGIN_BASE_PACKAGE_DESCRIPTOR"
  fi
}

wp_plugin_base_require_package_input() {
  if [ -n "${WP_PLUGIN_BASE_PACKAGE_DESCRIPTOR:-}" ]; then
    python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" assert-input "$WP_PLUGIN_BASE_PACKAGE_DESCRIPTOR" "$1" "$2"
  fi
}

wp_plugin_base_require_package_assets() {
  if [ -n "${WP_PLUGIN_BASE_PACKAGE_DESCRIPTOR:-}" ]; then
    python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" assert-assets "$WP_PLUGIN_BASE_PACKAGE_DESCRIPTOR" "$@"
  fi
}
