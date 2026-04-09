#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOOLS_DIR="${1:-$ROOT_DIR/.wp-plugin-base-tools}"
RUN_VALIDATION="${WP_PLUGIN_BASE_BOOTSTRAP_RUN_VALIDATION:-false}"

bash "$ROOT_DIR/scripts/ci/install_lint_tools.sh" "$TOOLS_DIR"

echo
printf 'Installed strict-local foundation tools into: %s\n' "$TOOLS_DIR"
printf 'Add to current shell PATH before strict-local validation:\n'
printf '  export PATH="%s:$PATH"\n' "$TOOLS_DIR"

if [ "$RUN_VALIDATION" = 'true' ]; then
  PATH="$TOOLS_DIR:$PATH" bash "$ROOT_DIR/scripts/foundation/validate.sh" --mode strict-local
fi
