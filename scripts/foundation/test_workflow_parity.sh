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

echo "Workflow parity tests passed for reusable and child-managed release/update workflows."
