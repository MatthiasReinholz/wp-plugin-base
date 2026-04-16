#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCHEMA_PATH="$ROOT_DIR/docs/config-schema.json"
LOAD_CONFIG_PATH="$ROOT_DIR/scripts/lib/load_config.sh"
ENV_EXAMPLE_PATH="$ROOT_DIR/templates/child/.wp-plugin-base.env.example"
README_PATH="$ROOT_DIR/README.md"

# shellcheck source=../lib/load_config.sh
. "$LOAD_CONFIG_PATH"

if [ ! -f "$SCHEMA_PATH" ]; then
  echo "Missing config schema: $SCHEMA_PATH" >&2
  exit 1
fi

jq -e '
  .schema_version == 1 and
  (.keys | type == "object") and
  (.scopes | type == "array") and
  (
    .keys
    | to_entries
    | all(
        (.value | type == "object") and
        (((.value.default // null) == null) or (.value.default | type == "string")) and
        (((.value.default_template // null) == null) or (.value.default_template | type == "string")) and
        (((.value.default // null) == null) or ((.value.default_template // null) == null))
      )
  )
' "$SCHEMA_PATH" >/dev/null

wp_plugin_base_expand_default_template() {
  local template="$1"

  perl -0pe 's/\$\{([A-Z0-9_]+)\}/defined $ENV{$1} ? $ENV{$1} : q()/ge' <<<"$template"
}

schema_keys="$(jq -r '.keys | keys[]' "$SCHEMA_PATH" | sort)"

loader_keys="$({
  awk '/wp_plugin_base_is_supported_config_key\(\)/,/^}/' "$LOAD_CONFIG_PATH" \
    | sed -n 's/^[[:space:]]*\([A-Z0-9_|]*\))$/\1/p' \
    | tr '|' '\n' \
    | sed '/^$/d'
} | sort -u)"

if [ "$schema_keys" != "$loader_keys" ]; then
  echo "Config schema keys and load_config supported keys drifted." >&2
  echo "Schema keys:" >&2
  printf '%s\n' "$schema_keys" >&2
  echo "Loader keys:" >&2
  printf '%s\n' "$loader_keys" >&2
  exit 1
fi

readme_required_keys="$({
  awk '/^Required keys in `.wp-plugin-base.env`:/,/^Optional keys:/' "$README_PATH" \
    | grep -E '^- `' \
    | grep -oE '`[A-Z0-9_]+`' \
    | tr -d '`'
} | sort -u)"

schema_required_project_keys="$(jq -r '.keys | to_entries[] | select((.value.required_in_scopes // []) | index("project") != null) | .key' "$SCHEMA_PATH" | sort -u)"

if [ "$readme_required_keys" != "$schema_required_project_keys" ]; then
  echo "README required key list and config schema project-required keys drifted." >&2
  echo "README required keys:" >&2
  printf '%s\n' "$readme_required_keys" >&2
  echo "Schema required keys for project scope:" >&2
  printf '%s\n' "$schema_required_project_keys" >&2
  exit 1
fi

readme_optional_keys="$({
  awk '/^Optional keys:/,/^Use shell-safe `KEY=value` syntax\./' "$README_PATH" \
    | grep -E '^- `' \
    | grep -oE '`[A-Z0-9_]+`' \
    | tr -d '`'
} | sort -u)"

schema_optional_keys="$({
  comm -23 \
    <(printf '%s\n' "$schema_keys") \
    <(printf '%s\n' "$schema_required_project_keys")
} | sort -u)"

if [ "$readme_optional_keys" != "$schema_optional_keys" ]; then
  echo "README optional key list and config schema optional keys drifted." >&2
  echo "README optional keys:" >&2
  printf '%s\n' "$readme_optional_keys" >&2
  echo "Schema optional keys:" >&2
  printf '%s\n' "$schema_optional_keys" >&2
  exit 1
fi

env_example_required_keys="$({
  grep -E '^[A-Z][A-Z0-9_]*=' "$ENV_EXAMPLE_PATH" \
    | sed 's/=.*$//'
} | sort -u)"

if [ "$env_example_required_keys" != "$schema_required_project_keys" ]; then
  echo "Env example required keys and schema project-required keys drifted." >&2
  echo "Env example required keys:" >&2
  printf '%s\n' "$env_example_required_keys" >&2
  echo "Schema required keys for project scope:" >&2
  printf '%s\n' "$schema_required_project_keys" >&2
  exit 1
fi

env_example_optional_keys="$({
  grep -E '^# [A-Z][A-Z0-9_]*=' "$ENV_EXAMPLE_PATH" \
    | sed -E 's/^# ([A-Z][A-Z0-9_]*)=.*/\1/'
} | sort -u)"

if [ "$env_example_optional_keys" != "$schema_optional_keys" ]; then
  echo "Env example optional keys and schema optional keys drifted." >&2
  echo "Env example optional keys:" >&2
  printf '%s\n' "$env_example_optional_keys" >&2
  echo "Schema optional keys:" >&2
  printf '%s\n' "$schema_optional_keys" >&2
  exit 1
fi

contract_fixture="$(mktemp -d)"
trap 'rm -rf "$contract_fixture"' EXIT

cat > "$contract_fixture/.wp-plugin-base.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.5.0
PLUGIN_NAME="Contract Test"
PLUGIN_SLUG=contract-test
MAIN_PLUGIN_FILE=contract-test.php
ZIP_FILE=contract-test.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG

WP_PLUGIN_BASE_ROOT="$contract_fixture" wp_plugin_base_load_config ""

while IFS= read -r row; do
  key="$(jq -r '.[0]' <<<"$row")"
  default_value="$(jq -r '.[1]' <<<"$row")"
  default_template="$(jq -r '.[2]' <<<"$row")"
  [ -n "$key" ] || continue

  actual_value="${!key:-}"
  expected_value="$default_value"
  if [ -n "$default_template" ]; then
    expected_value="$(wp_plugin_base_expand_default_template "$default_template")"
  fi

  if [ "$actual_value" != "$expected_value" ]; then
    echo "Config schema default drifted for ${key}." >&2
    echo "Expected: $expected_value" >&2
    echo "Actual:   $actual_value" >&2
    exit 1
  fi
done < <(
  jq -c '
    .keys
    | to_entries[]
    | select((.value.default // null) != null or (.value.default_template // null) != null)
    | [.key, (.value.default // ""), (.value.default_template // "")]
  ' "$SCHEMA_PATH"
)

echo "Validated config contract schema parity."
