#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR"
# Enforce the child-owned manifest and every transitive package engine contract.
npm ci --engine-strict --no-audit --no-fund
# Apply reviewed npm backports even when the child-owned manifest has no
# postinstall step; repeated application is idempotent.
if [ -f npm-remediations.json ]; then
  node ../.wp-plugin-base/scripts/security/npm-remediation.mjs apply --project-root . >/dev/null
fi
npm run build
