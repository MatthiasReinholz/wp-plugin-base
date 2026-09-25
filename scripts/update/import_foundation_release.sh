#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The implementation and provenance verifier must come from an already trusted
# foundation installation, never from the tree being imported.
exec python3 "$SCRIPT_DIR/import_foundation_release.py" "$@"
