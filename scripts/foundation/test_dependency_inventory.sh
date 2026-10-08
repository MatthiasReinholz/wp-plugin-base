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

  fixture_dir="$(mktemp -d)" || return 1
  if ! rsync -a --exclude '.git' "$ROOT_DIR/" "$fixture_dir/"; then
    rm -rf "$fixture_dir"
    return 1
  fi
  printf '%s\n' "$fixture_dir"
}

pass_fixture=""
missing_dependabot_fixture=""
missing_lockfile_fixture=""
broken_pin_fixture=""
trap 'rm -rf "$pass_fixture" "$missing_dependabot_fixture" "$missing_lockfile_fixture" "$broken_pin_fixture"' EXIT
pass_fixture="$(make_fixture)"
bash "$VALIDATOR" "$pass_fixture" >/dev/null

missing_dependabot_fixture="$(make_fixture)"
ruby -ryaml -e '
  path = ARGV.fetch(0)
  config = YAML.load_file(path)
  config.fetch("updates").reject! do |entry|
    entry["package-ecosystem"] == "pip" && entry["directory"] == "/tools/python-semgrep"
  end
  File.write(path, YAML.dump(config))
' "$missing_dependabot_fixture/.github/dependabot.yml"
run_expected_failure "$missing_dependabot_fixture" "Dependency inventory validation unexpectedly passed when a required Dependabot entry was removed."

missing_lockfile_fixture="$(make_fixture)"
rm -f "$missing_lockfile_fixture/tools/markdownlint/package-lock.json"
run_expected_failure "$missing_lockfile_fixture" "Dependency inventory validation unexpectedly passed with a missing lockfile-backed dependency file."

broken_pin_fixture="$(make_fixture)"
perl -0pi -e "s/WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION='[0-9.]*'/WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION='9.9.9'/" "$broken_pin_fixture/scripts/lib/wordpress_tooling.sh"
run_expected_failure "$broken_pin_fixture" "Dependency inventory validation unexpectedly passed with a pin mismatch."

echo "Dependency inventory fixture tests passed."
