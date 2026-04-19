#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "foundation release metadata generation" jq

VERSION="${1:-}"
COMMIT_SHA="${2:-}"
OUTPUT_PATH="${3:-}"
SOURCE_PROVIDER="${4:-${FOUNDATION_RELEASE_SOURCE_PROVIDER:-github-release}}"
SOURCE_REFERENCE="${5:-${FOUNDATION_RELEASE_SOURCE_REFERENCE:-${GITHUB_REPOSITORY:-}}}"
SOURCE_API_BASE="${6:-${FOUNDATION_RELEASE_SOURCE_API_BASE:-}}"

if [ -z "$VERSION" ] || [ -z "$COMMIT_SHA" ] || [ -z "$OUTPUT_PATH" ]; then
  echo "Usage: $0 <version> <commit-sha> <output-path> [provider] [reference] [api-base]" >&2
  exit 1
fi

if [ -z "$SOURCE_REFERENCE" ]; then
  echo "Foundation release source reference is required." >&2
  exit 1
fi

if [ -z "$SOURCE_API_BASE" ]; then
  SOURCE_API_BASE="$(wp_plugin_base_provider_default_api_base "$SOURCE_PROVIDER")"
fi

jq -n \
  --arg provider "$SOURCE_PROVIDER" \
  --arg reference "$SOURCE_REFERENCE" \
  --arg api_base "$SOURCE_API_BASE" \
  --arg version "$VERSION" \
  --arg commit "$COMMIT_SHA" '
  {
    release_source: {
      provider: $provider,
      reference: $reference,
      api_base: $api_base
    },
    version: $version,
    commit: $commit
  }
  + (if $provider == "github-release" then { repository: $reference } else {} end)
' > "$OUTPUT_PATH"

echo "Wrote foundation release metadata to ${OUTPUT_PATH}"
