#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

strict=false
if [ "${1:-}" = "--strict" ] || [ "${WP_PLUGIN_BASE_STRICT_LINTERS:-false}" = "true" ]; then
  strict=true
fi

if ! command -v shellcheck >/dev/null 2>&1; then
  if [ "$strict" = true ]; then
    echo "shellcheck is required for shell linting." >&2
    exit 1
  fi

  echo "shellcheck not installed; skipping shell lint."
  exit 0
fi

shell_files=()
while IFS= read -r file; do
  shell_files+=("$file")
done < <(find "$ROOT_DIR" \
  -path "$ROOT_DIR/.git" -prune -o \
  -path "$ROOT_DIR/node_modules" -prune -o \
  -path "$ROOT_DIR/dist" -prune -o \
  -type f -name '*.sh' -print | sort)

if [ "${#shell_files[@]}" -eq 0 ]; then
  echo "No shell files found."
  exit 0
fi

shellcheck_excludes='SC1091,SC2016,SC2034,SC2094,SC2129'

shellcheck -x -e "$shellcheck_excludes" "${shell_files[@]}"
echo "Shell lint passed."
