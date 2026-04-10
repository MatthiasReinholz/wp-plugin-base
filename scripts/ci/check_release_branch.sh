#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

BRANCH_NAME="${1:-}"

if [ -z "$BRANCH_NAME" ]; then
  echo "Usage: $0 branch-name [config-path]" >&2
  exit 1
fi

wp_plugin_base_load_config "${2:-}"
wp_plugin_base_require_vars README_FILE

README_PATH="$(wp_plugin_base_resolve_path "$README_FILE")"

if [[ ! "$BRANCH_NAME" =~ ^(release|hotfix)/([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  echo "Skipping release branch validation for $BRANCH_NAME."
  exit 0
fi

VERSION="${BASH_REMATCH[2]}"

bash "$SCRIPT_DIR/check_versions.sh" "$VERSION" "${2:-}"

if ! grep -q "^= $VERSION =$" "$README_PATH"; then
  echo "$README_FILE is missing a changelog section for version $VERSION." >&2
  exit 1
fi

section_contents="$(
  awk -v version="$VERSION" '
    $0 == "= " version " =" {
      in_section=1
      next
    }
    in_section && /^= .* =$/ {
      exit
    }
    in_section {
      print
    }
  ' "$README_PATH"
)"

if ! printf '%s\n' "$section_contents" | grep -q '^\* '; then
  echo "$README_FILE changelog entry for version $VERSION does not contain any bullet items." >&2
  exit 1
fi

saw_bullet=false
saw_blank_after_bullet=false
while IFS= read -r line; do
  if [ -z "$line" ]; then
    if [ "$saw_bullet" = "true" ]; then
      saw_blank_after_bullet=true
    fi
    continue
  fi

  if [[ ! "$line" =~ ^\*\  ]]; then
    echo "$README_FILE changelog entry for version $VERSION contains a non-bullet line: $line" >&2
    exit 1
  fi

  if [[ ! "$line" =~ ^\*\ (Add|Fix|Tweak|Update|Dev)[[:space:]]- ]]; then
    echo "WARNING: $README_FILE changelog entry for version $VERSION is missing Add/Fix/Tweak/Update/Dev prefix: $line" >&2
  fi

  if [ "$saw_blank_after_bullet" = "true" ]; then
    echo "$README_FILE changelog entry for version $VERSION contains blank lines between bullets." >&2
    exit 1
  fi

  saw_bullet=true
done <<<"$section_contents"

echo "Verified release branch ${BRANCH_NAME}."
