#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "WooCommerce.com deployment" curl jq

VERSION="${1:-}"
CONFIG_OVERRIDE="${2:-}"
ZIP_PATH_OVERRIDE="${3:-}"

STATUS_ENDPOINT='https://woocommerce.com/wp-json/wc/submission/runner/v1/product/deploy/status'
UPLOAD_ENDPOINT='https://woocommerce.com/wp-json/wc/submission/runner/v1/product/deploy'

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z [config-path] [zip-path]" >&2
  exit 1
fi

wp_plugin_base_load_config "$CONFIG_OVERRIDE"
wp_plugin_base_require_vars ZIP_FILE

if [ -z "${WOOCOMMERCE_COM_PRODUCT_ID:-}" ]; then
  echo "WOOCOMMERCE_COM_PRODUCT_ID is empty; skipping WooCommerce.com deploy." >&2
  echo "WOOCOMMERCE_COM_DEPLOY status=skipped reason=missing_product_id version=${VERSION}"
  exit 0
fi

if [[ ! "$WOOCOMMERCE_COM_PRODUCT_ID" =~ ^[0-9]+$ ]]; then
  echo "WOOCOMMERCE_COM_PRODUCT_ID must be numeric, found: ${WOOCOMMERCE_COM_PRODUCT_ID}" >&2
  exit 1
fi

if [[ ! "${WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS:-30}" =~ ^[1-9][0-9]*$ ]]; then
  echo "WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS must be a positive integer, found: ${WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS}" >&2
  exit 1
fi

if wp_plugin_base_is_true "${WP_PLUGIN_BASE_REPAIR_MODE:-false}"; then
  echo "WooCommerce.com deploy skipped in repair mode (WP_PLUGIN_BASE_REPAIR_MODE=true)."
  echo "WOOCOMMERCE_COM_DEPLOY status=skipped reason=repair_mode version=${VERSION} product_id=${WOOCOMMERCE_COM_PRODUCT_ID}"
  exit 0
fi

if [ -z "${WOO_COM_USERNAME:-}" ] || [ -z "${WOO_COM_APP_PASSWORD:-}" ]; then
  echo "WOO_COM_USERNAME and WOO_COM_APP_PASSWORD must be set for WooCommerce.com deploy." >&2
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

ZIP_PATH="${ZIP_PATH_OVERRIDE:-$ROOT_DIR/dist/$ZIP_FILE}"
if [ ! -f "$ZIP_PATH" ]; then
  echo "WooCommerce.com deploy ZIP not found: $ZIP_PATH" >&2
  exit 1
fi

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

compare_semver() {
  local left="$1"
  local right="$2"
  local left_parts
  local right_parts
  local i
  IFS='.' read -r -a left_parts <<<"$left"
  IFS='.' read -r -a right_parts <<<"$right"

  for i in 0 1 2; do
    local l="${left_parts[$i]:-0}"
    local r="${right_parts[$i]:-0}"
    if [ "$l" -gt "$r" ]; then
      echo 1
      return 0
    fi
    if [ "$l" -lt "$r" ]; then
      echo -1
      return 0
    fi
  done

  echo 0
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
  :
elif [ -n "$status_code" ]; then
  echo "WooCommerce.com status API returned error code ${status_code}: ${status_message}" >&2
  exit 1
else
  current_status="$(read_json_string "$status_json" '.status')"
  current_version="$(read_json_string "$status_json" '.version')"

  if [ "$current_status" = "queued" ] || [ "$current_status" = "running" ]; then
    echo "WooCommerce.com already has a deployment in progress for product ${WOOCOMMERCE_COM_PRODUCT_ID} (status=${current_status}, version=${current_version})." >&2
    exit 1
  fi

  if [[ "$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    semver_comparison="$(compare_semver "$current_version" "$VERSION")"
    if [ "$semver_comparison" -gt 0 ]; then
      echo "WooCommerce.com already has a higher version (${current_version}) for product ${WOOCOMMERCE_COM_PRODUCT_ID}; refusing to deploy ${VERSION}." >&2
      exit 1
    fi
  fi

  if [ "$current_version" = "$VERSION" ] && [ "$current_status" != "failed" ]; then
    echo "WooCommerce.com product ${WOOCOMMERCE_COM_PRODUCT_ID} is already on version ${VERSION} (status=${current_status}); skipping deploy."
    echo "WOOCOMMERCE_COM_DEPLOY status=skipped reason=already_live version=${VERSION} product_id=${WOOCOMMERCE_COM_PRODUCT_ID}"
    exit 0
  fi
fi

if ! http_post_multipart "$UPLOAD_ENDPOINT" \
  -F "file=@${ZIP_PATH}" \
  -F "product_id=${WOOCOMMERCE_COM_PRODUCT_ID}" \
  -F "version=${VERSION}" \
  -F "username=<${WOO_USERNAME_FILE}" \
  -F "password=<${WOO_PASSWORD_FILE}"
then
  echo "WooCommerce.com upload request failed before receiving an HTTP response." >&2
  exit 1
fi

if [[ ! "$HTTP_CODE" =~ ^[0-9]{3}$ ]]; then
  echo "WooCommerce.com upload request returned an invalid HTTP status code: ${HTTP_CODE}" >&2
  exit 1
fi

upload_json="$HTTP_BODY"

upload_code="$(read_json_string "$upload_json" '.code')"
upload_message="$(read_json_string "$upload_json" '.message // .error')"

if [ "$HTTP_CODE" -ge 400 ]; then
  if [ -n "$upload_code" ] || [ -n "$upload_message" ]; then
    echo "WooCommerce.com upload API request failed (HTTP ${HTTP_CODE}): ${upload_code} ${upload_message}" >&2
  else
    echo "WooCommerce.com upload API request failed (HTTP ${HTTP_CODE}). Response: ${upload_json}" >&2
  fi
  exit 1
fi

assert_valid_json "$upload_json" "upload response"

if [ -n "$upload_code" ]; then
  echo "WooCommerce.com deploy API returned error code ${upload_code}: ${upload_message}" >&2
  exit 1
fi

upload_status="$(read_json_string "$upload_json" '.status')"
if [ -z "$upload_status" ]; then
  upload_status='queued'
fi
queue_id="$(read_json_string "$upload_json" '.success // .queue_id // .id')"

if [ "$upload_status" = "failed" ]; then
  failure_reason="$(read_json_string "$upload_json" '.reason // .message // .error')"
  if [ -z "$failure_reason" ]; then
    failure_reason='unknown'
  fi
  echo "WooCommerce.com deployment failed immediately: ${failure_reason}" >&2
  exit 1
fi

printf 'WOOCOMMERCE_COM_DEPLOY status=%s version=%s product_id=%s queue_id=%s\n' \
  "$upload_status" \
  "$VERSION" \
  "$WOOCOMMERCE_COM_PRODUCT_ID" \
  "$queue_id"
