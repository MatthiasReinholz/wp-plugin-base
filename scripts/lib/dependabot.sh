#!/usr/bin/env bash

# Keep one renderer for ecosystem selection and foundation action ownership.
wp_plugin_base_render_dependabot() {
  local template="$1"
  local library_dir
  library_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ruby "$library_dir/../update/render_child_dependabot.rb" "$template" "$ROOT_DIR" \
    "${ADMIN_UI_PACK_ENABLED:-false}" "${DEPENDABOT_ECOSYSTEMS:-auto}"
}
