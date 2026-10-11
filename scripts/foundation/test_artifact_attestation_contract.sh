#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$fixture/"
config="$fixture/.wp-plugin-base.env"
cp "$config" "$fixture/original-config"

WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/write_config_outputs.sh" project "$config" "$fixture/defaults"
grep -Fxq 'github_artifact_attestations_enabled=true' "$fixture/defaults"
for value in true false; do
  cp "$fixture/original-config" "$config"
  printf '\nGITHUB_ARTIFACT_ATTESTATIONS_ENABLED=%s\n' "$value" >> "$config"
  WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/write_config_outputs.sh" project "$config" "$fixture/$value"
  grep -Fxq "github_artifact_attestations_enabled=$value" "$fixture/$value"
done
for value in invalid TRUE 0; do
  cp "$fixture/original-config" "$config"
  printf '\nGITHUB_ARTIFACT_ATTESTATIONS_ENABLED=%s\n' "$value" >> "$config"
  if WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/write_config_outputs.sh" project "$config" "$fixture/invalid" >/dev/null 2>&1; then
    echo 'Invalid attestation configuration must fail before writing workflow outputs.' >&2
    exit 1
  fi
  test ! -e "$fixture/invalid"
done

ruby -ryaml - "$ROOT_DIR" <<'RUBY'
root = ARGV.fetch(0)
setting = "steps.config.outputs.github_artifact_attestations_enabled == 'true'"
['.github/workflows', 'templates/child/.github/workflows'].each do |directory|
  ['finalize-release.yml', 'release.yml', 'publish-tag-release.yml'].each do |name|
    file = File.join(root, directory, name)
    next unless File.file?(file)
    steps = YAML.load_file(file).fetch('jobs').fetch('release').fetch('steps')
    attest = steps.select { |step| step['name'] == 'Attest package provenance' }
    raise "#{file}: expected exactly one attestation step" unless attest.length == 1
    prerequisite = case name
    when 'release.yml' then 'inputs.repair_host_assets && '
    when 'publish-tag-release.yml' then "steps.version.outputs.supported == 'true' && "
    else ''
    end
    raise "#{file}: incorrect attestation gate" unless attest.first['if'] == "${{ #{prerequisite}#{setting} }}"
    raise "#{file}: enabled attestation failures must block release" if attest.first['continue-on-error']
    steps.each do |step|
      next if step == attest.first
      raise "#{file}: attestation setting must not disable #{step['name']}" if step['if'].to_s.include?('github_artifact_attestations_enabled')
    end
  end
end
['finalize-foundation-release.yml', 'release-foundation.yml'].each do |name|
  file = File.join(root, '.github/workflows', name)
  raise "#{file}: plugin setting must not weaken foundation trust" if File.read(file).include?('github_artifact_attestations_enabled')
end
RUBY
echo 'Optional GitHub plugin attestations preserve all other release gates.'
