#!/usr/bin/env bash
# Invoke this reviewed helper before replacing a legacy project's vendor tree.
# It reads that project's existing templates but never executes candidate code.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/sync_child_repo.sh" --capture-automation-ownership "${1:-}"
