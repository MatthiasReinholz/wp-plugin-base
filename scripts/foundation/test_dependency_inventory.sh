#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/ci/validate_dependency_inventory.sh"

run_expected_failure() {
  local dir="$1"
  local message="$2"

  if bash "$VALIDATOR" "$dir" >/dev/null 2>&1; then
    echo "$message" >&2
    exit 1
  fi
}

make_fixture() {
  local fixture_dir

  fixture_dir="$(mktemp -d)"
  mkdir -p "$fixture_dir"
  rsync -a --exclude '.git' "$ROOT_DIR/" "$fixture_dir/"
  printf '%s\n' "$fixture_dir"
}

pass_fixture="$(make_fixture)"
trap 'rm -rf "$pass_fixture" "$missing_dependabot_fixture" "$missing_lockfile_fixture" "$broken_pin_fixture"' EXIT
bash "$VALIDATOR" "$pass_fixture" >/dev/null

missing_dependabot_fixture="$(make_fixture)"
perl -0pi -e 's/\n\s*- package-ecosystem: pip\n\s*directory: \/tools\/python-semgrep\n\s*schedule:\n\s*interval: weekly\n\s*open-pull-requests-limit: 10\n\s*commit-message:\n\s*prefix: chore\n\s*include: scope\n//' "$missing_dependabot_fixture/.github/dependabot.yml"
run_expected_failure "$missing_dependabot_fixture" "Dependency inventory validation unexpectedly passed when a required Dependabot entry was removed."

missing_lockfile_fixture="$(make_fixture)"
rm -f "$missing_lockfile_fixture/tools/markdownlint/package-lock.json"
run_expected_failure "$missing_lockfile_fixture" "Dependency inventory validation unexpectedly passed with a missing lockfile-backed dependency file."

broken_pin_fixture="$(make_fixture)"
perl -0pi -e "s/WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION='[0-9.]*'/WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION='9.9.9'/" "$broken_pin_fixture/scripts/lib/wordpress_tooling.sh"
run_expected_failure "$broken_pin_fixture" "Dependency inventory validation unexpectedly passed with a pin mismatch."

echo "Dependency inventory fixture tests passed."
