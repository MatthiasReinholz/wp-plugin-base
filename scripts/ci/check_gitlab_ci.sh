#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

CONFIG_OVERRIDE="${1:-}"

wp_plugin_base_require_commands "GitLab CI validation" ruby grep
wp_plugin_base_load_config "$CONFIG_OVERRIDE"

gitlab_ci_path="$(wp_plugin_base_resolve_path ".gitlab-ci.yml")"
if [ ! -f "$gitlab_ci_path" ]; then
  echo "GitLab automation requires .gitlab-ci.yml. Run .wp-plugin-base/scripts/update/sync_child_repo.sh." >&2
  exit 1
fi

ruby -e '
  require "yaml"
  YAML.safe_load(
    File.read(ARGV[0]),
    permitted_classes: [],
    aliases: true
  )
' "$gitlab_ci_path" >/dev/null

# This is an offline structural check only. It intentionally avoids the GitLab
# CI Lint API so local validation stays host-independent and does not require
# network credentials. Use the GitLab UI or runner lint tooling for full
# semantic pipeline validation when needed.
if ruby -e '
  content = File.read(ARGV[0])
  download_pattern = "(?:cu" + "rl|wg" + "et)"
  execute_pattern = "(?:ba" + "sh|s" + "h|zs" + "h|da" + "sh|ks" + "h|pws" + "h|pyth" + "on[0-9.]*|nod" + "e(?:js)?|pe" + "rl|ru" + "by|p" + "hp)"
  pattern = Regexp.new("\\b#{download_pattern}\\b[^\\n|]*(?:\\||&&\\s*)#{execute_pattern}\\b")
  exit(content.match?(pattern) ? 0 : 1)
' "$gitlab_ci_path"; then
  echo ".gitlab-ci.yml must not download and immediately execute remote scripts." >&2
  exit 1
fi

echo "Validated GitLab CI configuration at ${gitlab_ci_path}"
