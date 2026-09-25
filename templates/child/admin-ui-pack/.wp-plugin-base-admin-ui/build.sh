#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR"
# Enforce the child-owned manifest and every transitive package engine contract.
npm ci --engine-strict --no-audit --no-fund
npm run build
