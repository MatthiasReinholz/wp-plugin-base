#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$(mktemp -d)"

cleanup() {
  rm -rf "$FIXTURE"
}

trap cleanup EXIT

cat > "$FIXTURE/VERSION" <<'EOF'
v9.9.9
EOF

cat > "$FIXTURE/CHANGELOG.md" <<'EOF'
# Changelog

## v9.9.9

* Current release.

## Unreleased

* Stale draft note.
EOF

if WP_PLUGIN_BASE_ROOT="$FIXTURE" bash "$ROOT_DIR/scripts/foundation/check_version.sh" "v9.9.9" >/dev/null 2>&1; then
  echo "Foundation version validation unexpectedly accepted a persistent Unreleased section." >&2
  exit 1
fi

if WP_PLUGIN_BASE_ROOT="$FIXTURE" bash "$ROOT_DIR/scripts/foundation/bump_version.sh" "v9.9.10" >/dev/null 2>&1; then
  echo "Foundation version bump unexpectedly accepted a persistent Unreleased section." >&2
  exit 1
fi

if [ "$(tr -d '\n' < "$FIXTURE/VERSION")" != "v9.9.9" ]; then
  echo "Foundation version bump mutated VERSION before rejecting a persistent Unreleased section." >&2
  exit 1
fi

cat > "$FIXTURE/CHANGELOG.md" <<'EOF'
# Changelog

## v9.9.9

* Current release.
EOF

WP_PLUGIN_BASE_ROOT="$FIXTURE" bash "$ROOT_DIR/scripts/foundation/check_version.sh" "v9.9.9" >/dev/null

echo "Validated foundation changelog policy."
