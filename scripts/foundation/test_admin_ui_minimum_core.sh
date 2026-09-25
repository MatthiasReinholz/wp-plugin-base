#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$fixture/"
printf '\nADMIN_UI_STARTER=dataviews\n' >> "$fixture/.wp-plugin-base.env"
check_rejection() {
  if WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/check_admin_ui_pack.sh" > "$fixture/check.log" 2>&1; then
    echo 'DataViews accepted unsupported core metadata.' >&2
    exit 1
  fi
  grep -Fq 'Requires at least: 7.1 or newer' "$fixture/check.log"
}
check_rejection
perl -0pi -e 's/Plugin Name: Runtime Pack Ready/Plugin Name: Runtime Pack Ready\n * Requires at least: 6.9/' "$fixture/runtime-pack-ready.php"
check_rejection
perl -pi -e 's/Requires at least: 6.9/Requires at least: 7.1/' "$fixture/runtime-pack-ready.php"
check_rejection
perl -0pi -e 's/^Stable tag:/Requires at least: 7.1\nStable tag:/m' "$fixture/readme.txt"
# With supported metadata, validation proceeds to the next actual artifact gate.
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/check_admin_ui_pack.sh" > "$fixture/check.log" 2>&1; then
  echo 'Missing build wrapper unexpectedly accepted.' >&2
  exit 1
fi
grep -Fq 'Configured BUILD_SCRIPT does not exist' "$fixture/check.log"
echo 'DataViews minimum WordPress metadata contract passed.'
