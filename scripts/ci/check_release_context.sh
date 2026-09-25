#!/usr/bin/env bash
# Validate the reviewed application's publication profile and exact signer branch.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"
wp_plugin_base_load_config "${1:-}"
wp_plugin_base_require_managed_automation "Release automation"
workflow_branch="${2:-}"
wp_plugin_base_valid_branch "$workflow_branch" || { echo "Invalid release workflow branch." >&2; exit 1; }
case "${3:-false}" in
  true) ;; # Recovery verifies the historical tag's exact signing identity.
  false)
    if [ "$DEFAULT_BRANCH" != "$workflow_branch" ]; then
      echo "Release configuration DEFAULT_BRANCH must match the trusted workflow branch; historical host repair needs its original protected signing branch." >&2
      exit 1
    fi
    ;;
  *) echo "Historical recovery flag must be true or false." >&2; exit 1 ;;
esac
