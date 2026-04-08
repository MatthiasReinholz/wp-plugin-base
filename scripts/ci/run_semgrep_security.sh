#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

CONFIG_OVERRIDE="${1:-}"
OUTPUT_PATH="${2:-}"

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

if ! command -v semgrep >/dev/null 2>&1; then
  echo "semgrep is required for the Semgrep security pass." >&2
  exit 1
fi

semgrep_args=(
  --error
  --no-git-ignore
  --config "$SCRIPT_DIR/semgrep-rules/wordpress-security.yml"
  --exclude "$ROOT_DIR/.git"
  --exclude "$ROOT_DIR/.github"
  --exclude "$ROOT_DIR/.wp-plugin-base"
  --exclude "$ROOT_DIR/.wp-plugin-base-quality-pack"
  --exclude "$ROOT_DIR/.wp-plugin-base-security-pack"
  --exclude "$ROOT_DIR/dist"
  --exclude "$ROOT_DIR/node_modules"
  --exclude "$ROOT_DIR/tests"
  --exclude "$ROOT_DIR/vendor"
  "$ROOT_DIR"
)

if [ -n "$OUTPUT_PATH" ]; then
  mkdir -p "$(dirname "$OUTPUT_PATH")"
  semgrep_args=(--sarif --output "$OUTPUT_PATH" "${semgrep_args[@]}")
fi

semgrep "${semgrep_args[@]}"
