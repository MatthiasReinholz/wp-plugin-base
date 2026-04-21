#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$repo_root"
git config core.hooksPath .githooks

echo "Configured git hooks path to .githooks"
echo "Pre-push now runs local workflow-equivalent checks."
