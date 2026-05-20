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
workflow_dirs=()

append_workflow_dir() {
  local dir="$1"
  local existing

  [ -d "$dir" ] || return 0

  if [ "${workflow_dirs+x}" = x ]; then
    for existing in "${workflow_dirs[@]}"; do
      if [ "$existing" = "$dir" ]; then
        return 0
      fi
    done
  fi

  workflow_dirs+=("$dir")
}

append_workflow_dir "$ROOT_DIR/.github/workflows"
if [ -d "$ROOT_DIR/templates/child" ]; then
  while IFS= read -r dir; do
    append_workflow_dir "$dir"
  done < <(find "$ROOT_DIR/templates/child" -type d -path '*/.github/workflows' | sort)
fi

if [ "${#workflow_dirs[@]}" -eq 0 ]; then
  echo "No workflow files found."
  exit 0
fi

while IFS= read -r file; do
  workflow_files+=("$file")
done < <(find "${workflow_dirs[@]}" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)

if [ "${#workflow_files[@]}" -eq 0 ]; then
  echo "No workflow files found."
  exit 0
fi

actionlint "${workflow_files[@]}"
echo "Workflow lint passed."
