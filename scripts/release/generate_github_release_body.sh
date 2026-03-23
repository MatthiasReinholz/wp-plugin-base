#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

VERSION="${1:-}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z [config-path]" >&2
  exit 1
fi

wp_plugin_base_load_config "${2:-}"
wp_plugin_base_require_vars PLUGIN_NAME README_FILE ZIP_FILE

README_PATH="$(wp_plugin_base_resolve_path "$README_FILE")"

section="$(
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

if [ -z "$section" ]; then
  echo "Could not find changelog entry for version $VERSION in $README_FILE." >&2
  exit 1
fi

cat <<EOF
# ${PLUGIN_NAME} ${VERSION}

## Changes

${section}

## Install

Use \`${ZIP_FILE}\` below to install or update the plugin in WordPress.

GitHub also provides automatic source code archives for each release. Those archives are repository snapshots and are not the recommended plugin install package.
EOF
