#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"
EXPECTED_VERSION="${1:-}"
CURRENT_VERSION="$(tr -d '\n' < "$VERSION_FILE")"

if ! [[ "$CURRENT_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION does not contain a valid foundation version." >&2
  exit 1
fi

if [ -n "$EXPECTED_VERSION" ] && [ "$EXPECTED_VERSION" != "$CURRENT_VERSION" ]; then
  echo "Tag ${EXPECTED_VERSION} does not match foundation version ${CURRENT_VERSION}." >&2
  exit 1
fi

if ! grep -q "^## ${CURRENT_VERSION}$" "$CHANGELOG_FILE"; then
  echo "CHANGELOG.md is missing a section for ${CURRENT_VERSION}." >&2
  exit 1
fi

echo "Verified foundation version ${CURRENT_VERSION}."
