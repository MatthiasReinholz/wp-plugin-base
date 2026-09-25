#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

image="${WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGE:-}"
if [[ ! "$image" =~ ^[A-Za-z0-9./:_-]+@sha256:[a-f0-9]{64}$ ]]; then
  echo 'WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGE must identify a digest-pinned runtime image.' >&2
  exit 1
fi
if [ "${WP_PLUGIN_BASE_GITLAB_BOOTSTRAP_APT:-false}" = true ]; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl git jq nodejs npm perl php-cli python3 rsync ruby subversion unzip zip
fi
for command_name in git php node npm ruby perl python3 jq rsync curl zip unzip; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Runtime image is missing $command_name; provision the pinned GitLab image before use." >&2
    exit 1
  fi
done
wp_plugin_base_load_config "${1:-}"
expected_php="${WP_PLUGIN_BASE_EXPECTED_PHP_VERSION:-$PHP_VERSION}"
actual_php="$(php -r 'echo PHP_VERSION;')"
actual_node="$(node -p 'process.versions.node')"
version_matches() {
  [[ "$1" = "$2" || "$1" = "$2".* ]]
}
if ! version_matches "$actual_php" "$expected_php" || ! version_matches "$actual_node" "$NODE_VERSION"; then
  echo "GitLab image runtime mismatch: PHP $actual_php / Node $actual_node; configured PHP $expected_php / Node $NODE_VERSION." >&2
  echo 'Use a reviewed digest-pinned image with the configured versions and WP_PLUGIN_BASE_GITLAB_BOOTSTRAP_APT=false. See docs/automation-hosts.md.' >&2
  exit 1
fi
printf 'Verified GitLab runtime: PHP %s, Node %s.\n' "$actual_php" "$actual_node"
