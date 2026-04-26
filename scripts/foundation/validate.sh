#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

ASSURANCE_MODE="${WP_PLUGIN_BASE_ASSURANCE_MODE:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      if [ "$#" -lt 2 ]; then
        echo "--mode requires a value." >&2
        exit 1
      fi
      ASSURANCE_MODE="$2"
      shift 2
      ;;
    --mode=*)
      ASSURANCE_MODE="${1#*=}"
      shift
      ;;
    *)
      echo "Usage: $0 [--mode fast-local|strict-local|ci]" >&2
      exit 1
      ;;
  esac
done

if [ -z "$ASSURANCE_MODE" ]; then
  if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    ASSURANCE_MODE="ci"
  elif [ "${WP_PLUGIN_BASE_STRICT_LINTERS:-false}" = "true" ]; then
    ASSURANCE_MODE="strict-local"
  else
    ASSURANCE_MODE="fast-local"
  fi
fi

case "$ASSURANCE_MODE" in
  fast-local)
    export WP_PLUGIN_BASE_STRICT_LINTERS='false'
    ;;
  strict-local|ci)
    export WP_PLUGIN_BASE_STRICT_LINTERS='true'
    ;;
  *)
    echo "Unsupported assurance mode: $ASSURANCE_MODE" >&2
    exit 1
    ;;
esac

wp_plugin_base_require_commands "foundation validation" git php node ruby perl rsync zip unzip jq

declare -a optional_lint_tools=(
  shellcheck
  actionlint
  yamllint
  markdownlint-cli2
  codespell
  editorconfig-checker
  gitleaks
)
declare -a missing_optional_lint_tools=()

for tool in "${optional_lint_tools[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing_optional_lint_tools+=("$tool")
  fi
done

echo "Foundation assurance mode: $ASSURANCE_MODE"
if [ "${#missing_optional_lint_tools[@]}" -gt 0 ]; then
  missing_tools_csv="$(printf '%s, ' "${missing_optional_lint_tools[@]}")"
  missing_tools_csv="${missing_tools_csv%, }"

  if [ "$ASSURANCE_MODE" = "fast-local" ]; then
    echo "Optional foundation tools not installed; fast-local mode will skip: $missing_tools_csv"
  else
    echo "Assurance mode $ASSURANCE_MODE requires these installed foundation tools: $missing_tools_csv" >&2
    exit 1
  fi
fi

managed_child=""
managed_security_child=""

assert_regular_file() {
  local path="$1"
  local message="$2"

  if [ ! -f "$path" ]; then
    echo "$message" >&2
    exit 1
  fi
}

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

bash "$ROOT_DIR/scripts/foundation/run_foundation_policy_checks.sh" "$ROOT_DIR"

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
unset REST_OPERATIONS_PACK_ENABLED REST_API_NAMESPACE REST_ABILITIES_ENABLED ADMIN_UI_PACK_ENABLED
unset ADMIN_UI_STARTER ADMIN_UI_EXPERIMENTAL_DATAVIEWS
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
trap 'rm -rf "$managed_child" "$managed_security_child"' EXIT
mkdir -p "$managed_child/.wp-plugin-base"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$managed_child/"
rsync -a --exclude '.git' "$ROOT_DIR/" "$managed_child/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$managed_child" bash "$managed_child/.wp-plugin-base/scripts/update/sync_child_repo.sh"
test -f "$managed_child/.github/workflows/ci.yml"
test -f "$managed_child/.github/workflows/prepare-release.yml"
test -f "$managed_child/.github/workflows/finalize-release.yml"
test -f "$managed_child/.github/workflows/publish-tag-release.yml"
test -f "$managed_child/.github/workflows/release.yml"
test -f "$managed_child/.github/workflows/update-foundation.yml"
test -f "$managed_child/.github/dependabot.yml"
test -f "$managed_child/AGENTS.md"
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
grep -Fxq 'AGENTS.md' <<<"$managed_paths_output"
grep -Fq '/AGENTS.md export-ignore' "$managed_child/.gitattributes"
grep -Fq '/.wp-plugin-base-security-pack export-ignore' "$managed_child/.gitattributes"
grep -Fq '/.phpcs-security.xml.dist export-ignore' "$managed_child/.gitattributes"
grep -Fq 'secret-scan:' "$managed_child/.github/workflows/ci.yml"
test ! -f "$managed_child/.github/CODEOWNERS"

cat >> "$managed_child/.wp-plugin-base.env" <<'EOF'
CODEOWNERS_REVIEWERS="@example/platform @example/reviewer"
EOF
WP_PLUGIN_BASE_ROOT="$managed_child" bash "$managed_child/.wp-plugin-base/scripts/update/sync_child_repo.sh"
assert_regular_file "$managed_child/.github/CODEOWNERS" "Managed child CODEOWNERS file was not generated for CODEOWNERS_REVIEWERS."
assert_file_contains_literal "$managed_child/.github/CODEOWNERS" "@example/platform @example/reviewer" "Managed child CODEOWNERS file did not preserve multiple reviewers."

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
assert_regular_file "$managed_security_child/.phpcs-security.xml.dist" "Managed security pack is missing .phpcs-security.xml.dist."
assert_regular_file "$managed_security_child/.phpcs.xml.dist" "Managed quality pack is missing .phpcs.xml.dist."
assert_regular_file "$managed_security_child/.wp-plugin-base-security-pack/composer.json" "Managed security pack is missing composer.json."
assert_regular_file "$managed_security_child/.wp-plugin-base-security-pack/composer.lock" "Managed security pack is missing composer.lock."
assert_regular_file "$managed_security_child/.github/workflows/woocommerce-qit.yml" "Managed WooCommerce QIT workflow was not generated."
assert_file_omits_literal "$managed_security_child/.github/workflows/woocommerce-qit.yml" 'qit_cli_constraint' "Managed WooCommerce QIT workflow unexpectedly exposes qit_cli_constraint input."
assert_file_contains_literal "$managed_security_child/.github/workflows/ci.yml" 'Run Semgrep security scan' "Managed CI workflow is missing the Semgrep security scan job."
assert_file_contains_literal "$managed_security_child/.github/workflows/ci.yml" "WP_PLUGIN_BASE_SECURITY_PACK_SKIP_SEMGREP: 'true'" "Managed CI workflow is missing the Semgrep skip environment flag."
assert_file_contains_literal "$managed_security_child/.github/workflows/ci.yml" 'php-runtime-smoke:' "Managed CI workflow is missing the PHP runtime smoke job."
managed_security_paths_output="$(WP_PLUGIN_BASE_ROOT="$managed_security_child" bash "$ROOT_DIR/scripts/ci/list_managed_files.sh")"
bash "$ROOT_DIR/scripts/foundation/assert_foundation_contracts.sh" \
  "$ROOT_DIR" \
  "$managed_security_child" \
  "$managed_security_paths_output"
bash "$ROOT_DIR/scripts/foundation/run_release_security_smoke.sh" --mode local-lite
bash "$ROOT_DIR/scripts/foundation/test_rest_operations_pack_contracts.sh"
bash "$ROOT_DIR/scripts/foundation/test_rest_operations_pack_executor.sh"
bash "$ROOT_DIR/scripts/foundation/test_rest_operations_pack_abilities.sh"
bash "$ROOT_DIR/scripts/foundation/test_gitlab_support.sh"
bash "$ROOT_DIR/scripts/foundation/test_create_or_update_pr_auth_header_reset.sh"
bash "$ROOT_DIR/scripts/foundation/test_pr_changelog_body_extraction.sh"
bash "$ROOT_DIR/scripts/foundation/test_lint_pack_pruning.sh"
bash "$ROOT_DIR/scripts/foundation/test_run_quality_pack_local_fallback.sh"
bash "$ROOT_DIR/scripts/foundation/test_run_php_runtime_smoke_local_fallback.sh"
bash "$ROOT_DIR/scripts/foundation/test_woocommerce_qit_secret_scope.sh"

bash "$ROOT_DIR/scripts/foundation/run_release_update_fixture_checks.sh" "$ROOT_DIR"
echo "Validated foundation repository at $ROOT_DIR ($ASSURANCE_MODE)"
