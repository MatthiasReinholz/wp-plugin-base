#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/package_generation.sh
. "$SCRIPT_DIR/../lib/package_generation.sh"
wp_plugin_base_check_captured_package

SOURCE_PATH="${1:-}"
OUTPUT_PATH="${2:-}"

if [ -z "$SOURCE_PATH" ] || [ -z "$OUTPUT_PATH" ]; then
  echo "Usage: $0 <source-path> <output-path>" >&2
  exit 1
fi

if ! command -v syft >/dev/null 2>&1; then
  echo "syft is required to generate an SBOM." >&2
  exit 1
fi

if [ ! -e "$SOURCE_PATH" ]; then
  echo "SBOM source path not found: $SOURCE_PATH" >&2
  exit 1
fi

wp_plugin_base_require_package_input package_dir "$SOURCE_PATH"
wp_plugin_base_require_package_input sbom_path "$OUTPUT_PATH"
mkdir -p "$(dirname "$OUTPUT_PATH")"

SYFT_FORMAT_PRETTY=true syft "dir:${SOURCE_PATH}" -o "cyclonedx-json=${OUTPUT_PATH}" >/dev/null

echo "Generated SBOM at $OUTPUT_PATH"
