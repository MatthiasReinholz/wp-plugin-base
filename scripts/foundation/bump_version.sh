#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"
CHILD_ENV_EXAMPLE="$ROOT_DIR/templates/child/.wp-plugin-base.env.example"
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

if [ ! -f "$CHILD_ENV_EXAMPLE" ]; then
  echo "Missing child env example: $CHILD_ENV_EXAMPLE" >&2
  exit 1
fi

if ! grep -q '^FOUNDATION_VERSION=' "$CHILD_ENV_EXAMPLE"; then
  echo "Child env example is missing FOUNDATION_VERSION." >&2
  exit 1
fi

perl -0pe "s/^FOUNDATION_VERSION=.*/FOUNDATION_VERSION=$VERSION/m" "$CHILD_ENV_EXAMPLE" > "$CHANGELOG_TMP"
mv "$CHANGELOG_TMP" "$CHILD_ENV_EXAMPLE"

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
