#!/usr/bin/env bash

# Authenticate one Git command through process-local configuration only.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"
if [ -z "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
  echo 'GH_TOKEN or GITHUB_TOKEN is required for authenticated Git operations.' >&2
  exit 1
fi
wp_plugin_base_provider_git github "${GITHUB_API_URL:-https://api.github.com}" "$@"
