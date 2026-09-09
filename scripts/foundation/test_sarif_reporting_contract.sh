#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$fixture/"
config="$fixture/.wp-plugin-base.env"

WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/write_config_outputs.sh" project "$config" "$fixture/defaults"
grep -Fxq 'github_code_scanning_upload_enabled=true' "$fixture/defaults"
printf '\nGITHUB_CODE_SCANNING_UPLOAD_ENABLED=false\n' >> "$config"
WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/validate_config.sh" --scope project "$config"
WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/write_config_outputs.sh" project "$config" "$fixture/disabled"
grep -Fxq 'github_code_scanning_upload_enabled=false' "$fixture/disabled"
perl -pi -e 's/^GITHUB_CODE_SCANNING_UPLOAD_ENABLED=false$/GITHUB_CODE_SCANNING_UPLOAD_ENABLED=invalid/' "$config"
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/validate_config.sh" --scope project "$config" >/dev/null 2>&1; then
  echo 'Invalid reporting configuration must be rejected.' >&2
  exit 1
fi

ruby -ryaml - "$ROOT_DIR" <<'RUBY'
root = ARGV.fetch(0)
['.github/workflows/ci.yml', 'templates/child/.github/workflows/ci.yml'].each do |relative|
  workflow = YAML.load_file(File.join(root, relative))
  steps = workflow.fetch('jobs').fetch('wordpress-readiness').fetch('steps')
  by_name = steps.to_h { |step| [step['name'], step] }
  ['Run Semgrep security scan', 'Assert Semgrep SARIF exists', 'Upload Semgrep report artifact', 'Fail when Semgrep reports findings'].each do |name|
    raise "#{relative}: reporting setting must not disable #{name}" if by_name.fetch(name).fetch('if').include?('github_code_scanning_upload_enabled')
  end
  raise "#{relative}: dashboard upload must respect configuration" unless by_name.fetch('Upload Semgrep SARIF').fetch('if').include?("github_code_scanning_upload_enabled == 'true'")
  raise "#{relative}: report artifact must not silently disappear" unless by_name.fetch('Upload Semgrep report artifact').fetch('with').fetch('if-no-files-found') == 'error'
end
RUBY
echo 'SARIF reporting configuration preserves security enforcement.'
