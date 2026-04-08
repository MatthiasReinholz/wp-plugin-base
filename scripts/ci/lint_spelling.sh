#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

strict=false
if [ "${1:-}" = "--strict" ] || [ "${WP_PLUGIN_BASE_STRICT_LINTERS:-false}" = "true" ]; then
  strict=true
fi

if ! command -v codespell >/dev/null 2>&1; then
  if [ "$strict" = true ]; then
    echo "codespell is required for spelling linting." >&2
    exit 1
  fi

  echo "codespell not installed; skipping spelling lint."
  exit 0
fi

codespell --config "$ROOT_DIR/.codespellrc"
echo "Spelling lint passed."
