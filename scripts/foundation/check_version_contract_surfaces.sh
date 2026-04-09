#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${1:-$(tr -d '\n' < "$ROOT_DIR/VERSION")}"
CHILD_ENV_EXAMPLE="$ROOT_DIR/templates/child/.wp-plugin-base.env.example"

if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version contract check requires vX.Y.Z format, got: $VERSION" >&2
  exit 1
fi

if [ ! -f "$CHILD_ENV_EXAMPLE" ]; then
  echo "Missing child env example: $CHILD_ENV_EXAMPLE" >&2
  exit 1
fi

expected_line="FOUNDATION_VERSION=$VERSION"
if ! grep -Fxq "$expected_line" "$CHILD_ENV_EXAMPLE"; then
  echo "Child env example FOUNDATION_VERSION must match VERSION ($VERSION)." >&2
  exit 1
fi

echo "Verified version contract surfaces for $VERSION."
