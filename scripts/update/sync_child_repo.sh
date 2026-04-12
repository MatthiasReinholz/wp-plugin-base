#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/managed_files.sh
. "$SCRIPT_DIR/../lib/managed_files.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "managed file sync" perl
bash "$SCRIPT_DIR/../ci/validate_config.sh" --scope project "${1:-}"

wp_plugin_base_load_config "${1:-}"
wp_plugin_base_require_vars FOUNDATION_REPOSITORY FOUNDATION_VERSION PLUGIN_NAME PLUGIN_SLUG MAIN_PLUGIN_FILE README_FILE ZIP_FILE PHP_VERSION NODE_VERSION
CODEOWNERS_REVIEWERS="${CODEOWNERS_REVIEWERS:-}"
WORDPRESS_QUALITY_PACK_ENABLED="${WORDPRESS_QUALITY_PACK_ENABLED:-false}"
WORDPRESS_SECURITY_PACK_ENABLED="${WORDPRESS_SECURITY_PACK_ENABLED:-false}"
GITHUB_RELEASE_UPDATER_ENABLED="${GITHUB_RELEASE_UPDATER_ENABLED:-false}"
GITHUB_RELEASE_UPDATER_REPO_URL="${GITHUB_RELEASE_UPDATER_REPO_URL:-}"
GITHUB_RELEASE_UPDATER_MAIN_FILE_EXPR=""
if wp_plugin_base_is_true "$GITHUB_RELEASE_UPDATER_ENABLED"; then
  GITHUB_RELEASE_UPDATER_MAIN_FILE_EXPR="dirname( dirname( __DIR__ ) ) . '/$MAIN_PLUGIN_FILE'"
fi

FOUNDATION_DIR="$ROOT_DIR/.wp-plugin-base"
TEMPLATE_DIR="$FOUNDATION_DIR/templates/child"

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "Template directory not found: $TEMPLATE_DIR" >&2
  exit 1
fi

render_template() {
  local source_file="$1"
  local destination_file="$2"

  mkdir -p "$(dirname "$destination_file")"

  export FOUNDATION_REPOSITORY FOUNDATION_VERSION PRODUCTION_ENVIRONMENT CODEOWNERS_REVIEWERS
  export PLUGIN_NAME PLUGIN_SLUG MAIN_PLUGIN_FILE README_FILE ZIP_FILE PHP_VERSION NODE_VERSION VERSION_CONSTANT_NAME DISTIGNORE_FILE
  export WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE GITHUB_RELEASE_UPDATER_REPO_URL
  export GITHUB_RELEASE_UPDATER_MAIN_FILE_EXPR
  perl \
    -0pe 's~__FOUNDATION_REPOSITORY__~$ENV{FOUNDATION_REPOSITORY}~ge; s~__FOUNDATION_VERSION__~$ENV{FOUNDATION_VERSION}~ge; s~__PRODUCTION_ENVIRONMENT__~$ENV{PRODUCTION_ENVIRONMENT}~ge; s~__CODEOWNERS_REVIEWERS__~$ENV{CODEOWNERS_REVIEWERS}~ge; s~__PLUGIN_NAME__~$ENV{PLUGIN_NAME}~ge; s~__PLUGIN_SLUG__~$ENV{PLUGIN_SLUG}~ge; s~__MAIN_PLUGIN_FILE__~$ENV{MAIN_PLUGIN_FILE}~ge; s~__README_FILE__~$ENV{README_FILE}~ge; s~__ZIP_FILE__~$ENV{ZIP_FILE}~ge; s~__PHP_VERSION__~$ENV{PHP_VERSION}~ge; s~__NODE_VERSION__~$ENV{NODE_VERSION}~ge; s~__VERSION_CONSTANT_NAME__~$ENV{VERSION_CONSTANT_NAME}~ge; s~__DISTIGNORE_FILE__~$ENV{DISTIGNORE_FILE}~ge; s~__WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE__~$ENV{WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE}~ge; s~__GITHUB_RELEASE_UPDATER_REPO_URL__~$ENV{GITHUB_RELEASE_UPDATER_REPO_URL}~ge; s~__GITHUB_RELEASE_UPDATER_MAIN_FILE_EXPR__~$ENV{GITHUB_RELEASE_UPDATER_MAIN_FILE_EXPR}~ge' \
    "$source_file" > "$destination_file"
}

remove_stale_managed_aliases() {
  if [ "$DISTIGNORE_FILE" != ".distignore" ]; then
    rm -f "$ROOT_DIR/.distignore"
  fi

  if [ "$WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE" != ".wp-plugin-base-security-suppressions.json" ]; then
    rm -f "$ROOT_DIR/.wp-plugin-base-security-suppressions.json"
  fi
}

while IFS=$'\t' read -r source_file destination_path; do
  [ -n "$source_file" ] || continue
  if [ "$destination_path" = "$WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE" ] && [ -f "$ROOT_DIR/$destination_path" ]; then
    continue
  fi
  render_template "$source_file" "$ROOT_DIR/$destination_path"
done < <(wp_plugin_base_print_base_managed_template_pairs "$TEMPLATE_DIR")

remove_stale_managed_aliases

if [ -z "$CODEOWNERS_REVIEWERS" ]; then
  rm -f "$ROOT_DIR/.github/CODEOWNERS"
fi

if [ ! -f "$ROOT_DIR/CHANGELOG.md" ] && [ -f "$TEMPLATE_DIR/CHANGELOG.md" ]; then
  render_template "$TEMPLATE_DIR/CHANGELOG.md" "$ROOT_DIR/CHANGELOG.md"
fi

WOOCOMMERCE_STATUS_TEMPLATE_PATH="$TEMPLATE_DIR/.github/workflows/woocommerce-status.yml"
WOOCOMMERCE_STATUS_DESTINATION_PATH="$ROOT_DIR/.github/workflows/woocommerce-status.yml"
if [ -f "$WOOCOMMERCE_STATUS_TEMPLATE_PATH" ]; then
  if [ -n "${WOOCOMMERCE_COM_PRODUCT_ID:-}" ]; then
    render_template "$WOOCOMMERCE_STATUS_TEMPLATE_PATH" "$WOOCOMMERCE_STATUS_DESTINATION_PATH"
  else
    rm -f "$WOOCOMMERCE_STATUS_DESTINATION_PATH"
  fi
fi

QUALITY_PACK_TEMPLATE_DIR="$TEMPLATE_DIR/quality-pack"
SECURITY_PACK_TEMPLATE_DIR="$TEMPLATE_DIR/security-pack"
QIT_PACK_TEMPLATE_DIR="$TEMPLATE_DIR/qit-pack"
GITHUB_RELEASE_UPDATER_PACK_TEMPLATE_DIR="$TEMPLATE_DIR/github-release-updater-pack"

if [ -d "$QUALITY_PACK_TEMPLATE_DIR" ]; then
  rm -f "$ROOT_DIR/tests/test-plugin-loads.php"
  rm -f "$ROOT_DIR/tests/PluginLoadsTest.php"

  while IFS= read -r template_file; do
    [ -n "$template_file" ] || continue
    relative_path="${template_file#"$QUALITY_PACK_TEMPLATE_DIR"/}"
    destination_path="$ROOT_DIR/$relative_path"

    if wp_plugin_base_is_true "$WORDPRESS_QUALITY_PACK_ENABLED"; then
      render_template "$template_file" "$destination_path"
      continue
    fi

    rm -f "$destination_path"
  done < <(find "$QUALITY_PACK_TEMPLATE_DIR" -type f | sort)

  if ! wp_plugin_base_is_true "$WORDPRESS_QUALITY_PACK_ENABLED"; then
    find "$ROOT_DIR/.wp-plugin-base-quality-pack" -type d -empty -delete 2>/dev/null || true
    find "$ROOT_DIR/bin" -type d -empty -delete 2>/dev/null || true
    find "$ROOT_DIR/tests" -type d -empty -delete 2>/dev/null || true
  fi
fi

if [ -d "$SECURITY_PACK_TEMPLATE_DIR" ]; then
  while IFS= read -r template_file; do
    [ -n "$template_file" ] || continue
    relative_path="${template_file#"$SECURITY_PACK_TEMPLATE_DIR"/}"
    destination_path="$ROOT_DIR/$relative_path"

    if wp_plugin_base_is_true "$WORDPRESS_SECURITY_PACK_ENABLED"; then
      render_template "$template_file" "$destination_path"
      continue
    fi

    rm -f "$destination_path"
  done < <(find "$SECURITY_PACK_TEMPLATE_DIR" -type f | sort)

  if ! wp_plugin_base_is_true "$WORDPRESS_SECURITY_PACK_ENABLED"; then
    find "$ROOT_DIR/.wp-plugin-base-security-pack" -type d -empty -delete 2>/dev/null || true
  fi
fi

if [ -d "$QIT_PACK_TEMPLATE_DIR" ]; then
  while IFS= read -r template_file; do
    [ -n "$template_file" ] || continue
    relative_path="${template_file#"$QIT_PACK_TEMPLATE_DIR"/}"
    destination_path="$ROOT_DIR/$relative_path"

    if wp_plugin_base_is_true "$WOOCOMMERCE_QIT_ENABLED"; then
      render_template "$template_file" "$destination_path"
      continue
    fi

    rm -f "$destination_path"
  done < <(find "$QIT_PACK_TEMPLATE_DIR" -type f | sort)
fi

if [ -d "$GITHUB_RELEASE_UPDATER_PACK_TEMPLATE_DIR" ]; then
  while IFS= read -r template_file; do
    [ -n "$template_file" ] || continue
    relative_path="${template_file#"$GITHUB_RELEASE_UPDATER_PACK_TEMPLATE_DIR"/}"
    destination_path="$ROOT_DIR/$relative_path"

    if wp_plugin_base_is_true "$GITHUB_RELEASE_UPDATER_ENABLED"; then
      if [[ "$relative_path" == lib/wp-plugin-base/plugin-update-checker/* ]]; then
        mkdir -p "$(dirname "$destination_path")"
        cp "$template_file" "$destination_path"
        continue
      fi
      render_template "$template_file" "$destination_path"
      continue
    fi

    rm -f "$destination_path"
  done < <(find "$GITHUB_RELEASE_UPDATER_PACK_TEMPLATE_DIR" -type f | sort)

  if ! wp_plugin_base_is_true "$GITHUB_RELEASE_UPDATER_ENABLED"; then
    find "$ROOT_DIR/lib/wp-plugin-base/plugin-update-checker" -type d -empty -delete 2>/dev/null || true
    find "$ROOT_DIR/lib/wp-plugin-base" -type d -empty -delete 2>/dev/null || true
    find "$ROOT_DIR/lib" -type d -empty -delete 2>/dev/null || true
  fi
fi

echo "Synchronized managed project files."
