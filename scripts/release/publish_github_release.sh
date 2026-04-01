#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "GitHub release publication" gh

TAG_NAME="${1:-}"
RELEASE_TITLE="${2:-}"
NOTES_FILE="${3:-}"
shift 3 || true

if [ -z "$TAG_NAME" ] || [ -z "$RELEASE_TITLE" ] || [ -z "$NOTES_FILE" ]; then
  echo "Usage: $0 tag-name release-title notes-file [asset ...]" >&2
  exit 1
fi

if [ ! -f "$NOTES_FILE" ]; then
  echo "Release notes file not found: $NOTES_FILE" >&2
  exit 1
fi

if gh release view "$TAG_NAME" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
  gh release edit "$TAG_NAME" \
    --repo "${GITHUB_REPOSITORY}" \
    --title "$RELEASE_TITLE" \
    --notes-file "$NOTES_FILE"

  if [ "$#" -gt 0 ]; then
    gh release upload "$TAG_NAME" "$@" --repo "${GITHUB_REPOSITORY}" --clobber
  fi

  exit 0
fi

gh release create "$TAG_NAME" "$@" \
  --repo "${GITHUB_REPOSITORY}" \
  --title "$RELEASE_TITLE" \
  --notes-file "$NOTES_FILE"
