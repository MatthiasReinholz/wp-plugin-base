#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "WooCommerce.com deploy validation" perl unzip

VERSION="${1:-}"
CONFIG_OVERRIDE="${2:-}"
PACKAGE_DIR_OVERRIDE="${3:-}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z [config-path] [package-dir]" >&2
  exit 1
fi

wp_plugin_base_load_config "$CONFIG_OVERRIDE"
wp_plugin_base_require_vars PLUGIN_SLUG MAIN_PLUGIN_FILE ZIP_FILE

if [ -z "${WOOCOMMERCE_COM_PRODUCT_ID:-}" ]; then
  echo "WARNING: WOOCOMMERCE_COM_PRODUCT_ID is empty; skipping WooCommerce.com deployment preflight." >&2
  echo "WOOCOMMERCE_COM_PREFLIGHT status=skipped reason=missing_product_id version=${VERSION}"
  exit 0
fi

if [ -z "${WOO_COM_USERNAME:-}" ] || [ -z "${WOO_COM_APP_PASSWORD:-}" ]; then
  echo "WOO_COM_USERNAME and WOO_COM_APP_PASSWORD must be set for WooCommerce.com deploy." >&2
  exit 1
fi

if [[ ! "${WOOCOMMERCE_COM_PRODUCT_ID}" =~ ^[0-9]+$ ]]; then
  echo "WOOCOMMERCE_COM_PRODUCT_ID must be numeric, found: ${WOOCOMMERCE_COM_PRODUCT_ID}" >&2
  exit 1
fi

PACKAGE_DIR="${PACKAGE_DIR_OVERRIDE:-$ROOT_DIR/dist/package/$PLUGIN_SLUG}"
MAIN_PLUGIN_BASENAME="$(basename "$MAIN_PLUGIN_FILE")"
PACKAGE_PLUGIN_FILE="$PACKAGE_DIR/$MAIN_PLUGIN_BASENAME"
ZIP_PATH="$ROOT_DIR/dist/$ZIP_FILE"

if [ ! -d "$PACKAGE_DIR" ]; then
  echo "WooCommerce.com deploy source directory not found: $PACKAGE_DIR" >&2
  exit 1
fi

if [ ! -f "$PACKAGE_PLUGIN_FILE" ]; then
  echo "Packaged main plugin file not found: $PACKAGE_PLUGIN_FILE" >&2
  exit 1
fi

woo_header="$(perl -ne 'if (/^[ \t\/*#@ ]*Woo:(.*)$/) { $value = $1; $value =~ s/\s*(?:\*\/|\?>).*$//; $value =~ s/^\s+|\s+$//g; print "$value\n"; exit 0 }' "$PACKAGE_PLUGIN_FILE" || true)"

if [ -z "$woo_header" ]; then
  echo "Packaged plugin file is missing required Woo header (Woo: <product_id>:<hash>)." >&2
  exit 1
fi

IFS=':' read -r woo_header_product_id woo_header_hash woo_header_extra <<<"$woo_header"

if [ -n "${woo_header_extra:-}" ] || [[ ! "${woo_header_product_id:-}" =~ ^[0-9]+$ ]] || [[ ! "${woo_header_hash:-}" =~ ^[A-Za-z0-9]+$ ]]; then
  echo "Malformed Woo header in packaged plugin file. Expected Woo: <numeric_product_id>:<alphanumeric_hash>." >&2
  exit 1
fi

if [ "$woo_header_product_id" != "$WOOCOMMERCE_COM_PRODUCT_ID" ]; then
  echo "Woo header product id (${woo_header_product_id}) does not match WOOCOMMERCE_COM_PRODUCT_ID (${WOOCOMMERCE_COM_PRODUCT_ID})." >&2
  exit 1
fi

plugin_version="$(wp_plugin_base_read_header_value "$PACKAGE_PLUGIN_FILE" 'Version')"
if [ "$plugin_version" != "$VERSION" ]; then
  echo "Packaged plugin version ${plugin_version} does not match release version ${VERSION}." >&2
  exit 1
fi

if [ ! -f "$ZIP_PATH" ]; then
  echo "Packaged ZIP not found at expected path: $ZIP_PATH" >&2
  exit 1
fi

if ! unzip -tqq "$ZIP_PATH" >/dev/null 2>&1; then
  echo "Packaged ZIP failed integrity check: $ZIP_PATH" >&2
  exit 1
fi

echo "WOOCOMMERCE_COM_PREFLIGHT status=ready version=${VERSION} product_id=${WOOCOMMERCE_COM_PRODUCT_ID}"
