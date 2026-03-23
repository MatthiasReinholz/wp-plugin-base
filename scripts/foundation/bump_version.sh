#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"
VERSION="${1:-}"
NOTES_FILE="$(mktemp)"
CHANGELOG_TMP="$(mktemp)"

cleanup() {
  rm -f "$NOTES_FILE" "$CHANGELOG_TMP"
}

trap cleanup EXIT

if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 vX.Y.Z" >&2
  exit 1
fi

printf '%s\n' "$VERSION" > "$VERSION_FILE"

if ! grep -q "^## ${VERSION}$" "$CHANGELOG_FILE"; then
  bash "$ROOT_DIR/scripts/foundation/generate_release_notes.sh" "$VERSION" > "$NOTES_FILE"

  {
    echo "# Changelog"
    echo
    echo "## ${VERSION}"
    echo
    cat "$NOTES_FILE"
    echo
    tail -n +3 "$CHANGELOG_FILE"
  } > "$CHANGELOG_TMP"

  mv "$CHANGELOG_TMP" "$CHANGELOG_FILE"
fi

echo "Updated foundation version to $VERSION."
