#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "WooCommerce.com status check" curl jq

CONFIG_OVERRIDE="${1:-}"
wp_plugin_base_load_config "$CONFIG_OVERRIDE"

if [ -z "${WOO_COM_USERNAME:-}" ] || [ -z "${WOO_COM_APP_PASSWORD:-}" ]; then
  echo "WOO_COM_USERNAME and WOO_COM_APP_PASSWORD must be set for WooCommerce.com status checks." >&2
  exit 1
fi

if [ -z "${WOOCOMMERCE_COM_PRODUCT_ID:-}" ]; then
  echo "WOOCOMMERCE_COM_PRODUCT_ID must be set to query deployment status." >&2
  exit 1
fi

if [[ ! "$WOOCOMMERCE_COM_PRODUCT_ID" =~ ^[0-9]+$ ]]; then
  echo "WOOCOMMERCE_COM_PRODUCT_ID must be numeric, found: ${WOOCOMMERCE_COM_PRODUCT_ID}" >&2
  exit 1
fi

if [[ ! "${WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS:-30}" =~ ^[1-9][0-9]*$ ]]; then
  echo "WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS must be a positive integer, found: ${WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS}" >&2
  exit 1
fi

ENDPOINT_TIMEOUT_SECONDS="${WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS:-30}"
CONNECT_TIMEOUT_SECONDS="$ENDPOINT_TIMEOUT_SECONDS"
if [ "$CONNECT_TIMEOUT_SECONDS" -gt 10 ]; then
  CONNECT_TIMEOUT_SECONDS=10
fi

WOO_CREDENTIAL_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WOO_CREDENTIAL_DIR"
}
trap cleanup EXIT

WOO_USERNAME_FILE="$WOO_CREDENTIAL_DIR/username.txt"
WOO_PASSWORD_FILE="$WOO_CREDENTIAL_DIR/password.txt"
(
  umask 077
  printf '%s' "$WOO_COM_USERNAME" > "$WOO_USERNAME_FILE"
  printf '%s' "$WOO_COM_APP_PASSWORD" > "$WOO_PASSWORD_FILE"
)
unset WOO_COM_USERNAME WOO_COM_APP_PASSWORD

STATUS_ENDPOINT='https://woocommerce.com/wp-json/wc/submission/runner/v1/product/deploy/status'

HTTP_CODE=''
HTTP_BODY=''

http_post_multipart() {
  local endpoint="$1"
  shift
  local response
  if ! response="$(curl --show-error --silent \
    --connect-timeout "$CONNECT_TIMEOUT_SECONDS" \
    --max-time "$ENDPOINT_TIMEOUT_SECONDS" \
    -X POST "$endpoint" \
    "$@" \
    -w $'\n%{http_code}')"; then
    return 1
  fi

  HTTP_CODE="${response##*$'\n'}"
  HTTP_BODY="${response%$'\n'*}"
  return 0
}

read_json_string() {
  local json="$1"
  local expression="$2"
  printf '%s' "$json" | jq -r "$expression // \"\"" 2>/dev/null || true
}

assert_valid_json() {
  local json="$1"
  local context="$2"
  if ! printf '%s' "$json" | jq -e . >/dev/null 2>&1; then
    echo "WooCommerce.com ${context} returned invalid JSON: ${json}" >&2
    exit 1
  fi
}

if ! http_post_multipart "$STATUS_ENDPOINT" \
  -F "product_id=${WOOCOMMERCE_COM_PRODUCT_ID}" \
  -F "username=<${WOO_USERNAME_FILE}" \
  -F "password=<${WOO_PASSWORD_FILE}"
then
  echo "WooCommerce.com status request failed before receiving an HTTP response." >&2
  exit 1
fi

if [[ ! "$HTTP_CODE" =~ ^[0-9]{3}$ ]]; then
  echo "WooCommerce.com status request returned an invalid HTTP status code: ${HTTP_CODE}" >&2
  exit 1
fi

status_json="$HTTP_BODY"

status_code="$(read_json_string "$status_json" '.code')"
status_message="$(read_json_string "$status_json" '.message // .error')"

if [ "$HTTP_CODE" -ge 400 ]; then
  if [ -n "$status_code" ] || [ -n "$status_message" ]; then
    echo "WooCommerce.com status API request failed (HTTP ${HTTP_CODE}): ${status_code} ${status_message}" >&2
  else
    echo "WooCommerce.com status API request failed (HTTP ${HTTP_CODE}). Response: ${status_json}" >&2
  fi
  exit 1
fi

assert_valid_json "$status_json" "status response"

if [ "$status_code" = "submission_runner_no_deploy_in_progress" ]; then
  echo "WOOCOMMERCE_COM_STATUS status=idle product_id=${WOOCOMMERCE_COM_PRODUCT_ID}"
  exit 0
fi

if [ -n "$status_code" ]; then
  echo "WooCommerce.com status API returned error code ${status_code}: ${status_message}" >&2
  exit 1
fi

status_value="$(read_json_string "$status_json" '.status')"
if [ -z "$status_value" ]; then
  status_value='unknown'
fi
version_value="$(read_json_string "$status_json" '.version')"

printf 'WOOCOMMERCE_COM_STATUS status=%s product_id=%s version=%s\n' \
  "$status_value" \
  "$WOOCOMMERCE_COM_PRODUCT_ID" \
  "$version_value"

echo "$status_json"

if [ "$status_value" = "failed" ]; then
  exit 1
fi
