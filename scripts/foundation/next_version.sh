#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
RELEASE_TYPE="${1:-}"

if [ -z "$RELEASE_TYPE" ]; then
  echo "Usage: $0 major|minor|patch" >&2
  exit 1
fi

CURRENT_VERSION="$(tr -d '\n' < "$VERSION_FILE")"

if ! [[ "$CURRENT_VERSION" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Unable to parse current foundation version from VERSION." >&2
  exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

case "$RELEASE_TYPE" in
  major)
    major=$((major + 1))
    minor=0
    patch=0
    ;;
  minor)
    minor=$((minor + 1))
    patch=0
    ;;
  patch)
    patch=$((patch + 1))
    ;;
  *)
    echo "Unsupported release type: $RELEASE_TYPE" >&2
    exit 1
    ;;
esac

printf 'v%s.%s.%s\n' "$major" "$minor" "$patch"
