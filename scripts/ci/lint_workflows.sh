#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

strict=false
if [ "${1:-}" = "--strict" ] || [ "${WP_PLUGIN_BASE_STRICT_LINTERS:-false}" = "true" ]; then
  strict=true
fi

if ! command -v actionlint >/dev/null 2>&1; then
  if [ "$strict" = true ]; then
    echo "actionlint is required for workflow linting." >&2
    exit 1
  fi

  echo "actionlint not installed; skipping workflow lint."
  exit 0
fi

workflow_files=()
while IFS= read -r file; do
  workflow_files+=("$file")
done < <(find "$ROOT_DIR/.github/workflows" "$ROOT_DIR/templates/child/.github/workflows" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)

if [ "${#workflow_files[@]}" -eq 0 ]; then
  echo "No workflow files found."
  exit 0
fi

actionlint "${workflow_files[@]}"
echo "Workflow lint passed."
