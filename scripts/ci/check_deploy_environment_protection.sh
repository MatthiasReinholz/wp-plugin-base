#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

CONFIG_OVERRIDE="${1:-}"

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

if ! wp_plugin_base_is_true "${WP_ORG_DEPLOY_ENABLED:-false}"; then
  exit 0
fi

warning_prefix="Warning: WP_ORG_DEPLOY_ENABLED=true but deployment environment protection could not be fully verified."

if [ -z "${GITHUB_ACTIONS:-}" ] || [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "$warning_prefix Ensure environment '$PRODUCTION_ENVIRONMENT' exists and requires at least one reviewer." >&2
  exit 0
fi

if ! command -v gh >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "$warning_prefix Install gh and jq, or verify environment '$PRODUCTION_ENVIRONMENT' manually." >&2
  exit 0
fi

api_token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "$api_token" ]; then
  echo "$warning_prefix GH_TOKEN is unavailable, so environment '$PRODUCTION_ENVIRONMENT' must be verified manually." >&2
  exit 0
fi

if ! environment_json="$(GH_TOKEN="$api_token" gh api "repos/${GITHUB_REPOSITORY}/environments/${PRODUCTION_ENVIRONMENT}" 2>/dev/null)"; then
  echo "$warning_prefix Environment '$PRODUCTION_ENVIRONMENT' does not exist or could not be queried." >&2
  exit 0
fi

if ! printf '%s' "$environment_json" | jq -e 'any(.protection_rules[]?; .type == "required_reviewers" and ((.reviewers // []) | length) > 0)' >/dev/null; then
  echo "$warning_prefix Environment '$PRODUCTION_ENVIRONMENT' does not appear to require reviewers." >&2
  exit 0
fi

echo "Verified deployment environment protection for $PRODUCTION_ENVIRONMENT."
