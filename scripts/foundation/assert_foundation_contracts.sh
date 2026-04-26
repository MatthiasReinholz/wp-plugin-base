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
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'prepare_external_dependency_update.sh' "update-plugin-check workflow must route dependency updates through the shared preparation helper."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'cron: '\''17 5 * * 1'\''' "update-plugin-check workflow must remain scheduled."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'dependency_id:' "update-plugin-check workflow must define explicit dependency matrix coverage."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'plugin-update-checker-runtime' "update-plugin-check workflow must include plugin-update-checker-runtime updates."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'plugin-check' "update-plugin-check workflow must include plugin-check updates."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'composer-docker-image' "update-plugin-check workflow must include composer image digest updates."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'shellcheck-binary' "update-plugin-check workflow must include shellcheck binary updates."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'actionlint-binary' "update-plugin-check workflow must include actionlint binary updates."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'editorconfig-checker-binary' "update-plugin-check workflow must include editorconfig-checker updates."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'gitleaks-binary' "update-plugin-check workflow must include gitleaks updates."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'syft-binary' "update-plugin-check workflow must include syft updates."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'cosign-binary' "update-plugin-check workflow must include cosign updates."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'scripts/update/create_or_update_pr.sh' "update-plugin-check workflow must continue opening reviewable update PRs."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'scripts/foundation/validate.sh --mode ci' "update-plugin-check workflow must validate dependency updates before opening PRs."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'persist-credentials: false' "update-plugin-check workflow must disable checkout credential persistence so explicit PR tokens can authenticate git pushes."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" "secrets.WP_PLUGIN_BASE_PR_TOKEN != '' && secrets.WP_PLUGIN_BASE_PR_TOKEN || github.token" "update-plugin-check workflow must prefer the explicit PR token override when it is configured."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-foundation.yml" 'resolve_latest_foundation_version.sh' "update-foundation workflow must resolve candidate foundation releases."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-foundation.yml" 'install_release_security_tools.sh' "Root update-foundation workflow must install release security tooling before provenance verification."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-foundation.yml" 'wp-plugin-base-release-tools' "Root update-foundation workflow must add release security tools to PATH via GITHUB_PATH."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-foundation.yml" 'steps.latest.outputs.candidates' "Root update-foundation workflow must loop through release candidates."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-foundation.yml" 'steps.verify.outputs.version' "Root update-foundation workflow must use the verified foundation version output."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-foundation.yml" 'Validate updated child repository' "Root update-foundation workflow must validate the regenerated child repository before opening a PR."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-foundation.yml" 'persist-credentials: false' "Root update-foundation workflow must disable checkout credential persistence so explicit PR tokens can authenticate git pushes."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-foundation.yml" 'WP_PLUGIN_BASE_PR_TOKEN:' "Root update-foundation workflow must declare the optional workflow-write PR token secret."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-foundation.yml" "secrets.WP_PLUGIN_BASE_PR_TOKEN != '' && secrets.WP_PLUGIN_BASE_PR_TOKEN || github.token" "Root update-foundation workflow must prefer the explicit PR token override when it is configured."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/update-foundation.yml" 'steps.latest.outputs.candidates' "Child update-foundation workflow must loop through release candidates."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/update-foundation.yml" 'install_release_security_tools.sh' "Child update-foundation workflow must install release security tooling before provenance verification."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/update-foundation.yml" 'wp-plugin-base-release-tools' "Child update-foundation workflow must add release security tools to PATH via GITHUB_PATH."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/update-foundation.yml" 'steps.verify.outputs.version' "Child update-foundation workflow must use the verified foundation version output."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/update-foundation.yml" 'Validate updated child repository' "Child update-foundation workflow must validate the regenerated child repository before opening a PR."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/update-foundation.yml" 'persist-credentials: false' "Child update-foundation workflow must disable checkout credential persistence so explicit PR tokens can authenticate git pushes."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/update-foundation.yml" "secrets.WP_PLUGIN_BASE_PR_TOKEN != '' && secrets.WP_PLUGIN_BASE_PR_TOKEN || github.token" "Child update-foundation workflow must prefer the explicit PR token override when it is configured."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/prepare-release.yml" 'resolve_release_branch_source.sh' "Reusable prepare-release workflow must resolve the source ref through the shared helper."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/prepare-release.yml" 'Release base ref $BASE_REF must be main or a protected branch.' "Reusable prepare-release workflow must reject untrusted base refs before checkout."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/prepare-release.yml" 'persist-credentials: false' "Reusable prepare-release workflow must disable checkout credential persistence so explicit git auth does not add duplicate Authorization headers."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/prepare-foundation-release.yml" 'resolve_release_branch_source.sh' "Foundation prepare-release workflow must resolve the source ref through the shared helper."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/prepare-foundation-release.yml" 'Release base ref $BASE_REF must be main or a protected branch.' "Foundation prepare-release workflow must reject untrusted base refs before checkout."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/prepare-foundation-release.yml" 'persist-credentials: false' "Foundation prepare-release workflow must disable checkout credential persistence so explicit git auth does not add duplicate Authorization headers."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/prepare-release.yml" 'resolve_release_branch_source.sh' "Managed prepare-release workflow must resolve the source ref through the shared helper."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/prepare-release.yml" 'Release base ref $BASE_REF must be main or a protected branch.' "Managed prepare-release workflow must reject untrusted base refs before checkout."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/prepare-release.yml" 'persist-credentials: false' "Managed prepare-release workflow must disable checkout credential persistence so explicit git auth does not add duplicate Authorization headers."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/update-plugin-check.yml" 'GIT_ADD_PATHS: ${{ steps.prepare.outputs.git_add_paths }}' "update-plugin-check workflow must stage helper-provided dependency paths."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/release-foundation.yml" 'publish_github_release.sh --repair' "release-foundation workflow must publish in explicit repair mode."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/release.yml" 'ref: refs/tags/${{ steps.resolved.outputs.version }}' "Reusable manual release workflow must check out the exact existing tag ref."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/release-foundation.yml" 'ref: refs/tags/${{ inputs.version }}' "Foundation manual release workflow must check out the exact existing tag ref."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/release.yml" 'ref: refs/tags/${{ steps.version.outputs.value }}' "Managed manual release workflow must check out the exact existing tag ref."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/release.yml" 'Verify release tag is annotated' "Reusable manual release workflow must reject lightweight stable tags."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/release.yml" 'Verify release tag is annotated' "Managed manual release workflow must reject lightweight stable tags."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/release-foundation.yml" 'Verify release tag is annotated' "Foundation manual release workflow must reject lightweight stable tags."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/publish-tag-release.yml" 'Stable tag $tag is handled by the release PR/finalize flow' "Managed tag-push workflow must skip stable tags so finalize-release owns stable publication."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/publish-tag-release.yml" 'Verify tag comes from trusted history' "Managed tag-push workflow must verify prerelease tag provenance before publishing."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/publish-tag-release.yml" 'environment: __PRODUCTION_ENVIRONMENT__' "Managed tag-push workflow must use the protected production environment gate."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/publish-tag-release.yml" '--draft=false' "Managed tag-push workflow repair must clear draft state after assets are present."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/finalize-foundation-release.yml" 'Verify GitHub release' "Foundation finalizer must verify the published GitHub release and assets."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/finalize-foundation-release.yml" '--mark-latest' "Foundation finalizer must explicitly mark the current release as latest."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/finalize-release.yml" '--mark-latest' "Reusable finalizer must explicitly mark the current release as latest."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/finalize-release.yml" '--mark-latest' "Managed finalizer must explicitly mark the current release as latest."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/release.yml" 'verify_github_release_assets.sh' "Reusable manual release workflow must verify published GitHub release asset bytes."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/release.yml" 'verify_github_release_assets.sh' "Managed manual release workflow must verify published GitHub release asset bytes."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/finalize-release.yml" 'verify_github_release_assets.sh' "Reusable finalizer must verify published GitHub release asset bytes."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/finalize-release.yml" 'verify_github_release_assets.sh' "Managed finalizer must verify published GitHub release asset bytes."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/release-foundation.yml" 'dist-foundation-release.json.sigstore.json' "Foundation manual release workflow must verify signed release metadata assets."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/release.yml" 'WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY' "Reusable manual release workflow must require the explicit WordPress.org redeploy break-glass flag."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/release.yml" 'WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY' "Managed manual release workflow must require the explicit WordPress.org redeploy break-glass flag."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/finalize-release.yml" 'Deploy to WooCommerce.com Marketplace (post-publish)' "Reusable finalize-release workflow must include WooCommerce.com post-publish deploy."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/finalize-release.yml" 'Deploy to WooCommerce.com Marketplace (post-publish)' "Managed finalize-release workflow must include WooCommerce.com post-publish deploy."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/finalize-release.yml" 'Deploy to WordPress.org (post-publish)' "Reusable finalize-release workflow must deploy WordPress.org post-publish."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/finalize-release.yml" 'Deploy to WordPress.org (post-publish)' "Managed finalize-release workflow must deploy WordPress.org post-publish."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/release.yml" 'Deploy to WooCommerce.com Marketplace' "Reusable manual release workflow must include WooCommerce.com deploy repair path."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/release.yml" 'Deploy to WooCommerce.com Marketplace' "Managed manual release workflow must include WooCommerce.com deploy repair path."
assert_file_contains_literal "$ROOT_DIR/scripts/release/publish_github_release.sh" '--verify-tag' "GitHub release publication must verify that the tag already exists."
assert_file_contains_literal "$ROOT_DIR/scripts/release/publish_github_release.sh" '--draft=false' "GitHub release repair must clear draft state after assets are present."
assert_file_contains_literal "$ROOT_DIR/scripts/ci/install_lint_tools.sh" '--require-hashes' "Foundation lint tool bootstrap must install Python tools from hash-pinned requirements."
assert_file_contains_literal "$ROOT_DIR/scripts/ci/install_lint_tools.sh" 'npm ci --ignore-scripts --no-audit --no-fund' "Foundation lint tool bootstrap must install markdownlint from the committed npm lockfile."
assert_file_contains_literal "$ROOT_DIR/scripts/foundation/run_foundation_policy_checks.sh" 'test_validate_config_scope.sh' "Foundation policy checks must include config scope validation tests."
assert_file_contains_literal "$ROOT_DIR/scripts/foundation/run_foundation_policy_checks.sh" 'test_validate_config_runtime_pack_contracts.sh' "Foundation policy checks must include runtime-pack config contract tests."
assert_file_contains_literal "$ROOT_DIR/scripts/foundation/run_foundation_policy_checks.sh" 'test_admin_ui_api_client.sh' "Foundation policy checks must include the shared admin UI API client contract test."
assert_file_contains_literal "$ROOT_DIR/scripts/ci/validate_config.sh" 'config-schema.json' "Config validator must read the machine-readable config schema."
assert_file_contains_literal "$ROOT_DIR/scripts/ci/validate_config_contract.sh" 'README required key list and config schema project-required keys drifted' "Config contract parity validator must check README required keys against schema."
assert_file_contains_literal "$ROOT_DIR/scripts/ci/scan_rest_operation_contract.sh" 'rest-operation-manifest-contract.json' "REST operation contract scanning must read the canonical manifest contract file."
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
assert_file_contains_literal "$ROOT_DIR/docs/security-model.md" 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a' "Security documentation must advertise the reviewed upload-artifact SHA."
assert_file_contains_literal "$ROOT_DIR/.github/workflows/ci.yml" 'github/codeql-action/upload-sarif@95e58e9a2cdfd71adc6e0353d5c52f41a045d225' "Root CI workflow must pin upload-sarif to the reviewed SHA."
assert_file_contains_literal "$ROOT_DIR/templates/child/.github/workflows/ci.yml" 'github/codeql-action/upload-sarif@95e58e9a2cdfd71adc6e0353d5c52f41a045d225' "Child CI workflow must pin upload-sarif to the reviewed SHA."
assert_file_contains_literal "$ROOT_DIR/docs/security-model.md" 'github/codeql-action/upload-sarif@95e58e9a2cdfd71adc6e0353d5c52f41a045d225' "Security documentation must advertise the reviewed upload-sarif SHA."
assert_file_contains_literal "$ROOT_DIR/scripts/ci/audit_workflows.sh" 'github/codeql-action/upload-sarif@95e58e9a2cdfd71adc6e0353d5c52f41a045d225' "Workflow audit allowlist must include the reviewed upload-sarif SHA."
assert_file_contains_literal "$ROOT_DIR/docs/update-model.md" 'WP_PLUGIN_BASE_PR_TOKEN' "Update model documentation must explain the explicit PR token override for workflow-changing updates."
assert_file_contains_literal "$ROOT_DIR/docs/troubleshooting.md" 'WP_PLUGIN_BASE_PR_TOKEN' "Troubleshooting documentation must explain how to recover from workflow permission push failures."
assert_file_contains_literal "$ROOT_DIR/docs/security-model.md" 'workflow-changing update automation' "Security model documentation must document the narrow exception for workflow-writing PR tokens."
assert_file_contains_literal "$ROOT_DIR/templates/child/CONTRIBUTING.md" 'WP_PLUGIN_BASE_PR_TOKEN' "Managed child contributing guide must document the workflow-writing PR token override."
assert_file_omits_literal "$ROOT_DIR/templates/child/.github/workflows/ci.yml" 'github/codeql-action/upload-sarif@38697555549f1db7851b81482ff19f1fa5c4fedc' "Child CI workflow must not carry the stale upload-sarif SHA."
assert_file_omits_literal "$ROOT_DIR/docs/security-model.md" 'actions/upload-artifact@bbbca2ddaa5d8feaa63e36b76fdaad77386f024f' "Security documentation must not carry a stale upload-artifact SHA."
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
