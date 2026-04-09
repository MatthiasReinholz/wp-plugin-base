#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
NORMALIZER="$ROOT_DIR/scripts/ci/normalize_plugin_check_output.sh"

assert_json_equals() {
  local input="$1"
  local expected="$2"
  local actual

  actual="$(printf '%s' "$input" | bash "$NORMALIZER")"
  if [ "$(printf '%s\n' "$actual" | jq -c .)" != "$(printf '%s\n' "$expected" | jq -c .)" ]; then
    echo "Normalization mismatch." >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    exit 1
  fi
}

assert_json_equals '' '[]'
assert_json_equals 'Success: Checks complete. No errors found.' '[]'
assert_json_equals '[{"type":"WARNING","code":"X"}]' '[{"type":"WARNING","code":"X"}]'
assert_json_equals $'Prefix line\n[{"type":"ERROR","code":"Y"}]\n✔ Ran 12 checks' '[{"type":"ERROR","code":"Y"}]'

if printf 'totally not json' | bash "$NORMALIZER" >/dev/null 2>&1; then
  echo "Normalizer unexpectedly accepted malformed output without a recoverable JSON payload." >&2
  exit 1
fi

echo "Plugin Check normalization tests passed."
