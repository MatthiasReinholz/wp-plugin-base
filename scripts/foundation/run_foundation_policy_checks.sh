#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${1:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

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
bash "$ROOT_DIR/scripts/ci/validate_config_contract.sh"
bash "$ROOT_DIR/scripts/ci/validate_dependency_inventory.sh"
bash "$ROOT_DIR/scripts/foundation/test_validate_config_scope.sh"
bash "$ROOT_DIR/scripts/foundation/test_validate_config_runtime_pack_contracts.sh"
bash "$ROOT_DIR/scripts/foundation/test_admin_ui_api_client.sh"
bash "$ROOT_DIR/scripts/foundation/test_legacy_github_only_config.sh"
bash "$ROOT_DIR/scripts/foundation/test_foundation_release_metadata_backcompat.sh"
bash "$ROOT_DIR/scripts/foundation/test_dependency_inventory.sh"
bash "$ROOT_DIR/scripts/foundation/test_gitlab_release_flow_contracts.sh"
bash "$ROOT_DIR/scripts/foundation/test_plugin_check_output_normalization.sh"
bash "$ROOT_DIR/scripts/foundation/test_php_timeout_fallback.sh"
bash "$ROOT_DIR/scripts/foundation/test_workflow_parity.sh"
bash "$ROOT_DIR/scripts/foundation/test_create_or_update_pr_branch_safety.sh"
bash "$ROOT_DIR/scripts/foundation/test_create_or_update_pr_github_push_auth.sh"
bash "$ROOT_DIR/scripts/foundation/check_wordpress_env_tooling.sh"
