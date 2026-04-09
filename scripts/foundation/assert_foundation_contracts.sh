#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${1:?Usage: $0 <root-dir> <managed-security-child> <managed-security-paths-output>}"
MANAGED_SECURITY_CHILD="${2:?Usage: $0 <root-dir> <managed-security-child> <managed-security-paths-output>}"
MANAGED_SECURITY_PATHS_OUTPUT="${3:?Usage: $0 <root-dir> <managed-security-child> <managed-security-paths-output>}"

assert_file_contains_literal() {
  local path="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq -- "$needle" "$path"; then
    echo "$message" >&2
    exit 1
  fi
}

assert_file_omits_literal() {
  local path="$1"
  local needle="$2"
  local message="$3"

  if grep -Fq -- "$needle" "$path"; then
    echo "$message" >&2
    exit 1
  fi
}

assert_file_contains_literal "$ROOT_DIR/scripts/ci/run_plugin_check.sh" '/plugin-check/cli.php' "Plugin Check runner must bootstrap cli.php from the installed plugin."
assert_file_contains_literal "$ROOT_DIR/scripts/ci/run_plugin_check.sh" '--require="$plugin_check_cli_bootstrap"' "Plugin Check runner must require the resolved cli bootstrap path."
assert_file_contains_literal "$ROOT_DIR/scripts/ci/run_plugin_check.sh" 'normalize_plugin_check_output.sh' "Plugin Check runner must normalize CLI output through the shared parser."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'resolve_latest_plugin_check_version.sh' "update-plugin-check workflow must resolve the latest Plugin Check version."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'cron: '\''17 5 * * 1'\''' "update-plugin-check workflow must remain scheduled."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'WP_PLUGIN_BASE_PLUGIN_CHECK_ALLOWED_RELEASE_AUTHORS: davidperezgar' "update-plugin-check workflow must pin the reviewed plugin-check release author allowlist."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'WP_PLUGIN_BASE_PLUGIN_CHECK_MIN_RELEASE_AGE_DAYS: '\''7'\''' "update-plugin-check workflow must enforce the plugin-check stabilization window."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'write_external_github_dependency_pr_body.sh' "update-plugin-check workflow must use the shared external dependency PR-body helper."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'WP_PLUGIN_BASE_DEPENDENCY_TRUST_MODE: metadata-only' "update-plugin-check workflow must declare metadata-only trust for the external dependency PR warning."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-foundation.yml" 'resolve_latest_foundation_version.sh' "update-foundation workflow must resolve candidate foundation releases."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-foundation.yml" 'steps.latest.outputs.candidates' "Root update-foundation workflow must loop through release candidates."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-foundation.yml" 'steps.verify.outputs.version' "Root update-foundation workflow must use the verified foundation version output."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-foundation.yml" 'Validate updated child repository' "Root update-foundation workflow must validate the regenerated child repository before opening a PR."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/update-foundation.yml" 'steps.latest.outputs.candidates' "Child update-foundation workflow must loop through release candidates."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/update-foundation.yml" 'steps.verify.outputs.version' "Child update-foundation workflow must use the verified foundation version output."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/update-foundation.yml" 'Validate updated child repository' "Child update-foundation workflow must validate the regenerated child repository before opening a PR."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/prepare-release.yml" 'resolve_release_branch_source.sh' "Reusable prepare-release workflow must resolve the source ref through the shared helper."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/prepare-foundation-release.yml" 'resolve_release_branch_source.sh' "Foundation prepare-release workflow must resolve the source ref through the shared helper."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/prepare-release.yml" 'resolve_release_branch_source.sh' "Managed prepare-release workflow must resolve the source ref through the shared helper."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'GIT_ADD_PATHS: scripts/lib/wordpress_tooling.sh' "update-plugin-check workflow must stage the managed wordpress_tooling helper."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/release-foundation.yml" 'publish_github_release.sh --repair' "release-foundation workflow must publish in explicit repair mode."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/release.yml" 'ref: refs/tags/${{ steps.resolved.outputs.version }}' "Reusable manual release workflow must check out the exact existing tag ref."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/release-foundation.yml" 'ref: refs/tags/${{ inputs.version }}' "Foundation manual release workflow must check out the exact existing tag ref."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/release.yml" 'ref: refs/tags/${{ steps.version.outputs.value }}' "Managed manual release workflow must check out the exact existing tag ref."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/release.yml" 'WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY' "Reusable manual release workflow must require the explicit WordPress.org redeploy break-glass flag."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/release.yml" 'WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY' "Managed manual release workflow must require the explicit WordPress.org redeploy break-glass flag."
assert_file_contains_literal "$ROOT_DIR/scripts/release/publish_github_release.sh" '--verify-tag' "GitHub release publication must verify that the tag already exists."
assert_file_contains_literal "$ROOT_DIR/scripts/ci/install_lint_tools.sh" '--require-hashes' "Foundation lint tool bootstrap must install Python tools from hash-pinned requirements."
assert_file_contains_literal "$ROOT_DIR/scripts/ci/install_lint_tools.sh" 'npm ci --ignore-scripts --no-audit --no-fund' "Foundation lint tool bootstrap must install markdownlint from the committed npm lockfile."
assert_file_contains_literal "$ROOT_DIR/scripts/foundation/run_foundation_policy_checks.sh" 'test_validate_config_scope.sh' "Foundation policy checks must include config scope validation tests."
assert_file_contains_literal "$ROOT_DIR/scripts/ci/validate_config.sh" 'config-schema.json' "Config validator must read the machine-readable config schema."
assert_file_contains_literal "$ROOT_DIR/scripts/ci/validate_config_contract.sh" 'README required key list and config schema project-required keys drifted' "Config contract parity validator must check README required keys against schema."
assert_file_contains_literal "$ROOT_DIR/scripts/foundation/bootstrap_strict_local.sh" 'scripts/ci/install_lint_tools.sh' "Strict-local bootstrap must install audited lint/security tools."
assert_file_contains_literal "$ROOT_DIR/.github/dependabot.yml" 'directory: /tools/markdownlint' "Dependabot must manage markdownlint lockfile updates."
assert_file_contains_literal "$ROOT_DIR/.github/dependabot.yml" 'directory: /tools/python-lint-tools' "Dependabot must manage python lint tooling updates."
assert_file_contains_literal "$ROOT_DIR/.github/dependabot.yml" 'directory: /tools/python-semgrep' "Dependabot must manage Semgrep tooling updates."
assert_file_contains_literal "$ROOT_DIR/.github/dependabot.yml" 'directory: /templates/child/quality-pack/.wp-plugin-base-quality-pack' "Dependabot must manage quality-pack Composer updates."
assert_file_contains_literal "$ROOT_DIR/.github/dependabot.yml" 'directory: /templates/child/security-pack/.wp-plugin-base-security-pack' "Dependabot must manage security-pack Composer updates."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'concurrency:' "update-plugin-check workflow must serialize update automation."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-foundation.yml" 'concurrency:' "update-foundation workflow must serialize update automation."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/finalize-release.yml" 'concurrency:' "finalize-release workflow must serialize release publication."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/finalize-foundation-release.yml" 'concurrency:' "finalize-foundation-release workflow must serialize foundation release publication."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/ci.yml" 'github/codeql-action/upload-sarif@c10b8064de6f491fea524254123dbe5e09572f13' "Root CI workflow must pin upload-sarif to the reviewed SHA."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/ci.yml" 'github/codeql-action/upload-sarif@c10b8064de6f491fea524254123dbe5e09572f13' "Child CI workflow must pin upload-sarif to the reviewed SHA."
assert_file_contains_literal "$ROOT_DIR/docs/security-model.md" 'github/codeql-action/upload-sarif@c10b8064de6f491fea524254123dbe5e09572f13' "Security documentation must advertise the reviewed upload-sarif SHA."
assert_file_contains_literal "$ROOT_DIR/scripts/ci/audit_workflows.sh" 'github/codeql-action/upload-sarif@c10b8064de6f491fea524254123dbe5e09572f13' "Workflow audit allowlist must include the reviewed upload-sarif SHA."
assert_file_omits_literal "$ROOT_DIR/templates/child/.github/workflows/ci.yml" 'github/codeql-action/upload-sarif@38697555549f1db7851b81482ff19f1fa5c4fedc' "Child CI workflow must not carry the stale upload-sarif SHA."
assert_file_omits_literal "$ROOT_DIR/docs/security-model.md" 'github/codeql-action/upload-sarif@38697555549f1db7851b81482ff19f1fa5c4fedc' "Security documentation must not carry a stale upload-sarif SHA."
assert_file_omits_literal "$ROOT_DIR/scripts/ci/audit_workflows.sh" 'github/codeql-action/upload-sarif@38697555549f1db7851b81482ff19f1fa5c4fedc' "Workflow audit allowlist must not accept stale upload-sarif SHAs."

managed_semgrep_gate_pattern="$(cat <<'EOF_PATTERN'
if: ${{ always() && needs.validate.outputs.wordpress_security_pack_enabled == 'true' }}
EOF_PATTERN
)"
assert_file_contains_literal "$MANAGED_SECURITY_CHILD/.github/workflows/ci.yml" "$managed_semgrep_gate_pattern" "Managed CI workflow is missing the audited Semgrep gate condition."
grep -Fxq '.phpcs.xml.dist' <<<"$MANAGED_SECURITY_PATHS_OUTPUT" || { echo "Managed file list is missing .phpcs.xml.dist." >&2; exit 1; }
grep -Fxq '.phpcs-security.xml.dist' <<<"$MANAGED_SECURITY_PATHS_OUTPUT" || { echo "Managed file list is missing .phpcs-security.xml.dist." >&2; exit 1; }
grep -Fxq '.github/workflows/woocommerce-qit.yml' <<<"$MANAGED_SECURITY_PATHS_OUTPUT" || { echo "Managed file list is missing .github/workflows/woocommerce-qit.yml." >&2; exit 1; }

grep -Fxq "FOUNDATION_VERSION=$(tr -d '\n' < "$ROOT_DIR/VERSION")" "$ROOT_DIR/templates/child/.wp-plugin-base.env.example" || {
  echo "Child env example FOUNDATION_VERSION must match the repository VERSION." >&2
  exit 1
}
