#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
node .wp-plugin-base/scripts/security/npm-remediation.mjs apply --project-root . >/dev/null
npm run typecheck
npm run lint
npm test
npm run build
npm run test:runtime
