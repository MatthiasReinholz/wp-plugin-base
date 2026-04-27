#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

strict=false
if [ "${1:-}" = "--strict" ] || [ "${WP_PLUGIN_BASE_STRICT_LINTERS:-false}" = "true" ]; then
  strict=true
fi

if ! command -v yamllint >/dev/null 2>&1; then
  if [ "$strict" = true ]; then
    echo "yamllint is required for YAML linting." >&2
    exit 1
  fi

  echo "yamllint not installed; skipping YAML lint."
  exit 0
fi

yaml_files=()
while IFS= read -r file; do
  yaml_files+=("$file")
done < <(find "$ROOT_DIR" \
  -path "$ROOT_DIR/.git" -prune -o \
  -path "$ROOT_DIR/.wp-plugin-base-tools" -prune -o \
  -path "$ROOT_DIR/node_modules" -prune -o \
  -path "$ROOT_DIR/dist" -prune -o \
  -type f \( -name '*.yml' -o -name '*.yaml' \) -print | sort)

if [ "${#yaml_files[@]}" -eq 0 ]; then
  echo "No YAML files found."
  exit 0
fi

yamllint -c "$ROOT_DIR/.yamllint" "${yaml_files[@]}"
echo "YAML lint passed."
