#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

wp_plugin_base_load_config "${1:-}"
wp_plugin_base_require_vars FOUNDATION_REPOSITORY FOUNDATION_VERSION PRODUCTION_ENVIRONMENT

FOUNDATION_DIR="$ROOT_DIR/.wp-plugin-base"
TEMPLATE_DIR="$FOUNDATION_DIR/templates/child"

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "Template directory not found: $TEMPLATE_DIR" >&2
  exit 1
fi

render_template() {
  local source_file="$1"
  local destination_file="$2"

  mkdir -p "$(dirname "$destination_file")"

  export FOUNDATION_REPOSITORY FOUNDATION_VERSION PRODUCTION_ENVIRONMENT
  perl \
    -0pe 's~__FOUNDATION_REPOSITORY__~$ENV{FOUNDATION_REPOSITORY}~ge; s~__FOUNDATION_VERSION__~$ENV{FOUNDATION_VERSION}~ge; s~__PRODUCTION_ENVIRONMENT__~$ENV{PRODUCTION_ENVIRONMENT}~ge' \
    "$source_file" > "$destination_file"
}

render_template "$TEMPLATE_DIR/.distignore" "$ROOT_DIR/.distignore"
render_template "$TEMPLATE_DIR/CONTRIBUTING.md" "$ROOT_DIR/CONTRIBUTING.md"

while IFS= read -r template_file; do
  relative_path="${template_file#$TEMPLATE_DIR/}"
  render_template "$template_file" "$ROOT_DIR/$relative_path"
done < <(find "$TEMPLATE_DIR/.github" -type f | sort)

echo "Synchronized managed project files."
