#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

CONFIG_OVERRIDE=''
STRICT_MODE='false'

while [ "$#" -gt 0 ]; do
  case "$1" in
    --strict)
      STRICT_MODE='true'
      shift
      ;;
    *)
      if [ -n "${CONFIG_OVERRIDE:-}" ]; then
        echo "Only one config override path is supported." >&2
        exit 1
      fi
      CONFIG_OVERRIDE="$1"
      shift
      ;;
  esac
done

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

if ! wp_plugin_base_is_true "${WP_ORG_DEPLOY_ENABLED:-false}"; then
  exit 0
fi

report_violation() {
  local detail="$1"
  local prefix="WP_ORG_DEPLOY_ENABLED=true but deployment environment protection could not be fully verified."

  if [ "$STRICT_MODE" = 'true' ]; then
    echo "Error: $prefix $detail" >&2
    exit 1
  fi

  echo "Warning: $prefix $detail" >&2
  exit 0
}

if [ -z "${GITHUB_ACTIONS:-}" ] || [ -z "${GITHUB_REPOSITORY:-}" ]; then
  report_violation "Ensure environment '$PRODUCTION_ENVIRONMENT' exists and requires at least one reviewer."
fi

if ! command -v gh >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  report_violation "Install gh and jq, or verify environment '$PRODUCTION_ENVIRONMENT' manually."
fi

api_token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "$api_token" ]; then
  report_violation "GH_TOKEN is unavailable, so environment '$PRODUCTION_ENVIRONMENT' must be verified manually."
fi

query_environment() {
  GH_TOKEN="$api_token" gh api "repos/${GITHUB_REPOSITORY}/environments/${PRODUCTION_ENVIRONMENT}"
}

if ! environment_json="$(wp_plugin_base_run_with_retry 3 2 "Query deployment environment ${PRODUCTION_ENVIRONMENT}" query_environment 2>/dev/null)"; then
  report_violation "Environment '$PRODUCTION_ENVIRONMENT' does not exist or could not be queried."
fi

if ! printf '%s' "$environment_json" | jq -e 'any(.protection_rules[]?; .type == "required_reviewers" and ((.reviewers // []) | length) > 0)' >/dev/null; then
  report_violation "Environment '$PRODUCTION_ENVIRONMENT' does not appear to require reviewers."
fi

echo "Verified deployment environment protection for $PRODUCTION_ENVIRONMENT."
