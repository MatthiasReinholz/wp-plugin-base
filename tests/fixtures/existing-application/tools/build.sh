#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
npm run typecheck
npm run lint
npm test
npm run build
npm run test:runtime
