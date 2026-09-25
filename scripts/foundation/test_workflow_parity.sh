#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

assert_same_literal_presence() {
  local literal="$1"
  local file_a="$2"
  local file_b="$3"
  local label="$4"

  local has_a='false'
  local has_b='false'

  if grep -Fq -- "$literal" "$file_a"; then
    has_a='true'
  fi
  if grep -Fq -- "$literal" "$file_b"; then
    has_b='true'
  fi

  if [ "$has_a" != "$has_b" ]; then
    echo "$label drifted between workflow surfaces: $literal" >&2
    echo "  $file_a => $has_a" >&2
    echo "  $file_b => $has_b" >&2
    exit 1
  fi
}

assert_contains_literal() {
  local literal="$1"
  local file="$2"
  local label="$3"

  if ! grep -Fq -- "$literal" "$file"; then
    echo "$label is missing required literal: $literal" >&2
    exit 1
  fi
}

root_update="$ROOT_DIR/.github/workflows/update-foundation.yml"
child_update="$ROOT_DIR/templates/child/.github/workflows/update-foundation.yml"
root_finalize="$ROOT_DIR/.github/workflows/finalize-release.yml"
child_finalize="$ROOT_DIR/templates/child/.github/workflows/finalize-release.yml"

for file in "$root_update" "$child_update" "$root_finalize" "$child_finalize"; do
  if [ ! -f "$file" ]; then
    echo "Workflow parity file is missing: $file" >&2
    exit 1
  fi
done

assert_contains_literal 'concurrency:' "$root_update" 'Reusable update-foundation workflow'
assert_contains_literal 'concurrency:' "$child_update" 'Managed child update-foundation workflow'
assert_contains_literal 'concurrency:' "$root_finalize" 'Reusable finalize-release workflow'
assert_contains_literal 'concurrency:' "$child_finalize" 'Managed child finalize-release workflow'

for literal in \
  'resolve_latest_foundation_version.sh' \
  'install_release_security_tools.sh' \
  'verify_foundation_release.sh' \
  'sync_child_repo.sh' \
  'WP_PLUGIN_BASE_ACTION_MIGRATION_MANIFEST' \
  'list_migrated_action_paths.rb' \
  'validate_project.sh' \
  'create_or_update_pr.sh'
do
  assert_same_literal_presence "$literal" "$root_update" "$child_update" 'update-foundation logic'
done

for literal in \
  'generate_github_release_body.sh' \
  'install_release_security_tools.sh' \
  'generate_sbom.sh' \
  'sign_release.sh' \
  'publish_github_release.sh' \
  'deploy_woocommerce_com.sh' \
  'validate_woocommerce_com_deploy.sh' \
  'trigger_glotpress_import.sh' \
  'send_deploy_notification.sh'
do
  assert_same_literal_presence "$literal" "$root_finalize" "$child_finalize" 'finalize-release logic'
done

for file in "$root_finalize" "$child_finalize" \
  "$ROOT_DIR/.github/workflows/finalize-foundation-release.yml" \
  "$ROOT_DIR/.github/workflows/release-foundation.yml" \
  "$ROOT_DIR/.github/workflows/release.yml" \
  "$ROOT_DIR/templates/child/.github/workflows/release.yml" \
  "$ROOT_DIR/templates/child/.github/workflows/publish-tag-release.yml"; do
  # GitHub expressions must remain literal in policy checks.
  # shellcheck disable=SC2016
  assert_contains_literal 'group: release-publication-${{ github.repository }}' "$file" 'Shared publication concurrency'
done

# Ruby compares authored GitHub expressions, not shell substitutions.
# shellcheck disable=SC2016
ruby -ryaml -e '
  root = File.expand_path("../..", File.dirname(ARGV.first))
  publishing = Dir.glob(["#{root}/.github/workflows/*.yml", "#{root}/templates/child/.github/workflows/*.yml"]).select do |file|
    YAML.load_file(file).fetch("jobs", {}).values.any? do |job|
      job.fetch("steps", []).any? { |step| step["run"].to_s.match?(/publish_github_release\.sh|gh release (?:create|edit|upload)/) }
    end
  end
  abort "Publishing workflows missing policy coverage: #{publishing - ARGV}" unless (publishing - ARGV).empty?
  ARGV.each do |file|
    doc = YAML.load_file(file)
    job = doc.fetch("jobs").fetch("release")
    steps = job.fetch("steps")
    publish = steps.index { |step| step["run"].to_s.include?("publish_github_release.sh") }
    abort "Inline publication bypasses immutable payload checks: #{file}" unless publish
    if File.basename(file) != "publish-tag-release.yml"
      verify = steps.index { |step| step["name"] == "Verify signing identity before publication" }
      abort "Signing identity is not checked before publication: #{file}" unless verify && verify < publish
    end
    steps.each_with_index do |step, index|
      next unless step["run"].to_s.match?(/\/(?:deploy_wordpress_org|deploy_woocommerce_com)\.sh/)
      abort "Channel deploy precedes immutable host publication: #{file}" unless index > publish
    end
    if ["release.yml", "release-foundation.yml"].include?(File.basename(file))
      abort "Manual stable signing is not bound to main: #{file}" unless job["if"] == "${{ github.ref == \"refs/heads/main\" }}".tr("\"", "\x27")
    end
    if File.basename(file) == "release.yml"
      restore = steps.find { |step| step["run"].to_s.include?("restore_github_release_assets.sh") }
      abort "Default recovery does not restore verified bytes: #{file}" unless restore && restore["if"] == "${{ !inputs.repair_host_assets }}"
      abort "Host repair is not explicit: #{file}" unless steps[publish]["if"] == "${{ inputs.repair_host_assets }}"
    end
    steps.select { |step| step["uses"].to_s.start_with?("actions/checkout@") }.each do |step|
      abort "Checkout persists release credentials: #{file}" unless step.fetch("with")["persist-credentials"] == false
    end
    if File.basename(file).start_with?("finalize-")
      preserve = steps.index { |step| step["name"] == "Preserve current trusted release helpers" }
      detach = steps.index { |step| step["run"].to_s.include?("git checkout --detach") }
      abort "Historical checkout bypasses current release policy: #{file}" unless preserve && detach && preserve < detach
    else
      trusted = steps.find { |step| step["name"] == "Checkout current trusted release helpers" }
      abort "Recovery lacks protected-main helpers: #{file}" unless trusted && trusted.fetch("with")["ref"] == "main"
    end
    steps.each do |step|
      next unless step["run"].to_s.include?("publish_github_release.sh") || step["run"].to_s.include?("restore_github_release_assets.sh")
      abort "Release used historical policy helper: #{file}" unless step["run"].include?("$RUNNER_TEMP/wp-plugin-base-release-driver/scripts/release/")
    end
  end
' "$root_finalize" "$child_finalize" \
  "$ROOT_DIR/.github/workflows/finalize-foundation-release.yml" \
  "$ROOT_DIR/.github/workflows/release-foundation.yml" \
  "$ROOT_DIR/.github/workflows/release.yml" \
  "$ROOT_DIR/templates/child/.github/workflows/release.yml" \
  "$ROOT_DIR/templates/child/.github/workflows/publish-tag-release.yml"

echo "Workflow parity tests passed for reusable and child-managed release/update workflows."
