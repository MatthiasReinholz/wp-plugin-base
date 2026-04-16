#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "dependency inventory validation" jq ruby

TARGET_ROOT="${1:-$REPO_ROOT}"
TARGET_ROOT="$(cd "$TARGET_ROOT" && pwd -P)"

INVENTORY_PATH="$TARGET_ROOT/docs/dependency-inventory.json"
DEPENDABOT_PATH="$TARGET_ROOT/.github/dependabot.yml"

if [ ! -f "$INVENTORY_PATH" ]; then
  echo "Dependency inventory file is missing: $INVENTORY_PATH" >&2
  exit 1
fi

if [ ! -f "$DEPENDABOT_PATH" ]; then
  echo "Dependabot config is missing: $DEPENDABOT_PATH" >&2
  exit 1
fi

jq -e '
  .schema_version == 1 and
  (.dependencies | type == "array") and
  (.dependencies | length > 0) and
  (.dependencies | all(
    (.id | type == "string") and
    (.tier | type == "string") and
    (.update | type == "object") and
    (.update.kind | type == "string")
  ))
' "$INVENTORY_PATH" >/dev/null

required_ids=(
  github-actions-workflows
  wordpress-env-tooling
  admin-ui-basic-starter-tooling
  admin-ui-dataviews-starter-tooling
  markdownlint-tooling
  python-lint-tooling
  python-semgrep-tooling
  quality-pack-composer
  security-pack-composer
  plugin-update-checker-runtime
  plugin-check
  composer-docker-image
  shellcheck-binary
  actionlint-binary
  editorconfig-checker-binary
  gitleaks-binary
  syft-binary
  cosign-binary
)

for id in "${required_ids[@]}"; do
  if ! jq -e --arg id "$id" '.dependencies | any(.id == $id)' "$INVENTORY_PATH" >/dev/null; then
    echo "Dependency inventory is missing required dependency id: $id" >&2
    exit 1
  fi
done

# Ensure all declared lockfile-backed dependencies provide a lockfile path and the lockfile exists.
while IFS= read -r lockfile_path; do
  [ -n "$lockfile_path" ] || continue
  if [ ! -f "$TARGET_ROOT/$lockfile_path" ]; then
    echo "Declared dependency lockfile not found: $lockfile_path" >&2
    exit 1
  fi
done < <(jq -r '.dependencies[] | select(.tier == "lockfile-backed") | .lockfile // empty' "$INVENTORY_PATH")

# Verify pin patterns remain synchronized with the inventory contract.
while IFS=$'\t' read -r pin_file pin_pattern; do
  [ -n "$pin_file" ] || continue
  if [ ! -f "$TARGET_ROOT/$pin_file" ]; then
    echo "Pinned dependency file not found: $pin_file" >&2
    exit 1
  fi
  if ! grep -Fq -- "$pin_pattern" "$TARGET_ROOT/$pin_file"; then
    echo "Pinned dependency pattern not found in $pin_file: $pin_pattern" >&2
    exit 1
  fi
done < <(
  jq -r '.dependencies[] | select(.pin != null) | [.pin.file, .pin.pattern] | @tsv' "$INVENTORY_PATH"
)

# Validate dependabot coverage for inventory entries that declare dependabot automation.
while IFS=$'\t' read -r ecosystem directory; do
  [ -n "$ecosystem" ] || continue

  if ! ruby -rpsych -e '
    file = ARGV[0]
    ecosystem = ARGV[1]
    directory = ARGV[2]
    data = Psych.safe_load(File.read(file), aliases: false)
    updates = data.is_a?(Hash) ? Array(data["updates"]) : []
    found = updates.any? do |entry|
      entry.is_a?(Hash) && entry["package-ecosystem"] == ecosystem && entry["directory"] == directory
    end
    exit(found ? 0 : 1)
  ' "$DEPENDABOT_PATH" "$ecosystem" "$directory"; then
    echo "Dependabot coverage missing for ecosystem=$ecosystem directory=$directory" >&2
    exit 1
  fi
done < <(
  jq -r '.dependencies[] | select(.update.kind == "dependabot") | [.update.ecosystem, .update.directory] | @tsv' "$INVENTORY_PATH"
)

# Validate workflow-driven updater coverage for inventory entries that declare workflow automation.
while IFS= read -r workflow_path; do
  [ -n "$workflow_path" ] || continue
  if [ ! -f "$TARGET_ROOT/$workflow_path" ]; then
    echo "Declared dependency workflow not found: $workflow_path" >&2
    exit 1
  fi
done < <(
  jq -r '.dependencies[] | select(.update.kind == "workflow") | .update.path // empty' "$INVENTORY_PATH"
)

if ! grep -Fq 'prepare_external_dependency_update.sh' "$TARGET_ROOT/.github/workflows/update-plugin-check.yml"; then
  echo "update-plugin-check workflow must drive dependency updates through prepare_external_dependency_update.sh." >&2
  exit 1
fi

if ! grep -Fq 'wp plugin install plugin-check --version="$WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION" --activate' "$TARGET_ROOT/scripts/ci/run_plugin_check.sh"; then
  echo "Plugin Check runtime installer must remain pinned to WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION." >&2
  exit 1
fi

echo "Validated dependency inventory and update coverage."
