#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

strict=false
if [ "${1:-}" = "--strict" ] || [ "${WP_PLUGIN_BASE_STRICT_LINTERS:-false}" = "true" ]; then
  strict=true
fi

if ! command -v markdownlint-cli2 >/dev/null 2>&1; then
  if [ "$strict" = true ]; then
    echo "markdownlint-cli2 is required for Markdown linting." >&2
    exit 1
  fi

  echo "markdownlint-cli2 not installed; skipping Markdown lint."
  exit 0
fi

(
  cd "$ROOT_DIR"
  markdownlint-cli2 \
    --config ".markdownlint.jsonc" \
    "README.md" \
    "CHANGELOG.md" \
    "SECURITY.md" \
    "docs/**/*.md" \
    "templates/**/*.md" \
    "!templates/child/github-release-updater-pack/lib/wp-plugin-base/plugin-update-checker/**/*.md"
)

echo "Markdown lint passed."
