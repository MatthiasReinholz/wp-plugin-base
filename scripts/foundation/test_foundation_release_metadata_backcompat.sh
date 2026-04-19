#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

metadata_path="$(mktemp)"
trap 'rm -f "$metadata_path"' EXIT

bash "$ROOT_DIR/scripts/foundation/write_release_metadata.sh" \
  "v1.5.0" \
  "0123456789abcdef0123456789abcdef01234567" \
  "$metadata_path" \
  "github-release" \
  "MatthiasReinholz/wp-plugin-base" \
  "https://api.github.com"

jq -e '
  .repository == "MatthiasReinholz/wp-plugin-base"
  and .release_source.provider == "github-release"
  and .release_source.reference == "MatthiasReinholz/wp-plugin-base"
  and .release_source.api_base == "https://api.github.com"
  and .version == "v1.5.0"
' "$metadata_path" >/dev/null

echo "Foundation release metadata backward-compatibility test passed."
