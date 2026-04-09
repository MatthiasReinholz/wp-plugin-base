#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE_CONFIG="$ROOT_DIR/scripts/ci/validate_config.sh"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$fixture/"

cat > "$fixture/.wp-plugin-base.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG

WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project >/dev/null

cat > "$fixture/.scope-sync.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
EOF_CONFIG
WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope sync .scope-sync.env >/dev/null

cat > "$fixture/.scope-foundation.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
EOF_CONFIG
WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope foundation .scope-foundation.env >/dev/null

cat > "$fixture/.scope-deploy-missing-slug.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope deploy .scope-deploy-missing-slug.env >/dev/null 2>&1; then
  echo "Deploy scope unexpectedly passed without WORDPRESS_ORG_SLUG." >&2
  exit 1
fi

cat > "$fixture/.scope-project-missing-name.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project .scope-project-missing-name.env >/dev/null 2>&1; then
  echo "Project scope unexpectedly passed without PLUGIN_NAME." >&2
  exit 1
fi

cat > "$fixture/.scope-project-invalid-name.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
PLUGIN_NAME=
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project .scope-project-invalid-name.env >/dev/null 2>&1; then
  echo "Project scope unexpectedly passed with an empty PLUGIN_NAME." >&2
  exit 1
fi

cat > "$fixture/.scope-project-invalid-codeowners.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
CODEOWNERS_REVIEWERS=example/platform
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project .scope-project-invalid-codeowners.env >/dev/null 2>&1; then
  echo "Project scope unexpectedly passed with invalid CODEOWNERS_REVIEWERS format." >&2
  exit 1
fi

if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope invalid .wp-plugin-base.env >/dev/null 2>&1; then
  echo "Config validation unexpectedly accepted an invalid scope." >&2
  exit 1
fi

echo "Config scope validation tests passed."
