#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"
BRANCH_NAME="${1:-}"

if [ -z "$BRANCH_NAME" ]; then
  echo "Usage: $0 branch-name" >&2
  exit 1
fi

if [[ ! "$BRANCH_NAME" =~ ^(release|hotfix)/(v[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  echo "Skipping foundation release branch validation for $BRANCH_NAME."
  exit 0
fi

VERSION="${BASH_REMATCH[2]}"

bash "$ROOT_DIR/scripts/foundation/check_version.sh" "$VERSION"

section_contents="$(
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

if ! printf '%s\n' "$section_contents" | grep -q '^\* '; then
  echo "CHANGELOG.md entry for ${VERSION} does not contain any bullet items." >&2
  exit 1
fi

echo "Verified foundation release branch ${BRANCH_NAME}."
