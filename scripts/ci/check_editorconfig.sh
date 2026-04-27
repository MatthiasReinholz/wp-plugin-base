#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

strict=false
if [ "${1:-}" = "--strict" ] || [ "${WP_PLUGIN_BASE_STRICT_LINTERS:-false}" = "true" ]; then
  strict=true
fi

if ! command -v editorconfig-checker >/dev/null 2>&1; then
  if [ "$strict" = true ]; then
    echo "editorconfig-checker is required for EditorConfig validation." >&2
    exit 1
  fi

  echo "editorconfig-checker not installed; skipping EditorConfig validation."
  exit 0
fi

(
  cd "$ROOT_DIR"
  # Vendored third-party runtime files preserve upstream formatting.
  editorconfig-checker \
    -exclude '^(\.wp-plugin-base-tools/|templates/child/github-release-updater-pack/lib/wp-plugin-base/plugin-update-checker/)'
)

echo "EditorConfig validation passed."
