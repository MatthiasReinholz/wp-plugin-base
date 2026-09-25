#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/managed_files.sh
. "$SCRIPT_DIR/../lib/managed_files.sh"

MODE="validate"
CONFIG_OVERRIDE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      if [ "$#" -lt 2 ]; then
        echo "--mode requires a value." >&2
        exit 1
      fi
      MODE="$2"
      shift 2
      ;;
    --mode=*)
      MODE="${1#*=}"
      shift
      ;;
    *)
      CONFIG_OVERRIDE="$1"
      shift
      ;;
  esac
done

case "$MODE" in
  validate|stage)
    ;;
  *)
    echo "Unsupported mode: $MODE" >&2
    exit 1
    ;;
esac

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

collect_listed_managed_files() {
  case "$MODE" in
    validate)
      _wp_plugin_base_collect_managed_paths || return 1
      ;;
    stage)
      # Stage whole vendored trees so files retired upstream are also deleted.
      printf '%s\n' 'lib/wp-plugin-base/plugin-update-checker' || return 1
      _wp_plugin_base_collect_all_managed_paths || return 1
      _wp_plugin_base_collect_required_seed_paths || return 1
      ;;
  esac
}

_wp_plugin_base_emit_managed_manifest --unique collect_listed_managed_files
