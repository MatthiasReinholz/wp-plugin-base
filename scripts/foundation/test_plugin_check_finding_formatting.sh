#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FORMATTER="$ROOT_DIR/scripts/ci/format_plugin_check_findings.sh"

input='[
  {
    "type": "ERROR",
    "code": "outdated_tested_upto_header",
    "file": "readme.txt",
    "line": 5,
    "message": "<strong>Tested up to: 6.9 &lt; 7.0.</strong><br>The \"Tested up to\" value &amp; guidance."
  },
  {
    "type": "WARNING",
    "code": "reserved_code",
    "file": "",
    "line": 0,
    "message": " Second finding "
  }
]'

error_output="$(printf '%s\n' "$input" | bash "$FORMATTER" ERROR 10)"
expected_error='- outdated_tested_upto_header at readme.txt:5: Tested up to: 6.9 < 7.0. The "Tested up to" value & guidance.'

if [ "$error_output" != "$expected_error" ]; then
  echo "Plugin Check error finding formatting mismatch." >&2
  echo "Expected: $expected_error" >&2
  echo "Actual:   $error_output" >&2
  exit 1
fi

warning_output="$(printf '%s\n' "$input" | bash "$FORMATTER" WARNING 10)"
expected_warning='- reserved_code at (no file): Second finding'

if [ "$warning_output" != "$expected_warning" ]; then
  echo "Plugin Check warning finding formatting mismatch." >&2
  echo "Expected: $expected_warning" >&2
  echo "Actual:   $warning_output" >&2
  exit 1
fi

echo "Plugin Check finding formatting tests passed."
