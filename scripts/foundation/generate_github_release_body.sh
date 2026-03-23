#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"
VERSION="${1:-}"

if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 vX.Y.Z" >&2
  exit 1
fi

section="$(
  awk -v version="$VERSION" '
    $0 == "## " version {
      in_section=1
      next
    }
    in_section && /^## / {
      exit
    }
    in_section {
      print
    }
  ' "$CHANGELOG_FILE"
)"

if [ -z "$section" ]; then
  echo "Could not find CHANGELOG.md entry for ${VERSION}." >&2
  exit 1
fi

cat <<EOF
# wp-plugin-base ${VERSION}

## Changes

${section}
EOF
