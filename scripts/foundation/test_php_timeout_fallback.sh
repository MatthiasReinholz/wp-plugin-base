#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMEOUT_HELPER="$ROOT_DIR/scripts/ci/run_with_php_timeout.php"

stdout_file="$(mktemp)"
stderr_file="$(mktemp)"

cleanup() {
  rm -f "$stdout_file" "$stderr_file"
}

trap cleanup EXIT

php "$TIMEOUT_HELPER" 5 php -r 'fwrite(STDOUT, "stdout-ok\n"); fwrite(STDERR, "stderr-ok\n"); exit(0);' >"$stdout_file" 2>"$stderr_file"
grep -Fxq 'stdout-ok' "$stdout_file"
grep -Fxq 'stderr-ok' "$stderr_file"

set +e
php "$TIMEOUT_HELPER" 5 php -r 'fwrite(STDOUT, "stdout-fail\n"); fwrite(STDERR, "stderr-fail\n"); exit(7);' >"$stdout_file" 2>"$stderr_file"
status="$?"
set -e

if [ "$status" -ne 7 ]; then
  echo "Expected failed command to exit with status 7, got $status." >&2
  exit 1
fi
grep -Fxq 'stdout-fail' "$stdout_file"
grep -Fxq 'stderr-fail' "$stderr_file"

set +e
php "$TIMEOUT_HELPER" 1 php -r 'sleep(5);' >"$stdout_file" 2>"$stderr_file"
status="$?"
set -e

if [ "$status" -ne 124 ]; then
  echo "Expected timed-out command to exit with status 124, got $status." >&2
  exit 1
fi
grep -Fq 'Command timed out after 1' "$stderr_file"

echo "PHP timeout fallback tests passed."
