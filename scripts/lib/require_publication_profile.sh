#!/usr/bin/env bash
# Standalone signing/publishing also serve the foundation (which has no child
# config). Honor an explicit child config when present; never load candidate code.
_wp_plugin_base_publication_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=load_config.sh
. "$_wp_plugin_base_publication_lib/load_config.sh"
wp_plugin_base_require_publication_profile() {
  local root config
  root="$(wp_plugin_base_root)"
  config="$(wp_plugin_base_config_path "$root")"
  if [ -f "$config" ] || [ -n "${WP_PLUGIN_BASE_CONFIG:-}" ]; then
    wp_plugin_base_load_config
  fi
  wp_plugin_base_require_managed_automation "Release signing or publication"
}
