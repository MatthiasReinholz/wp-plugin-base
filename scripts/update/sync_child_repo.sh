#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/managed_files.sh
. "$SCRIPT_DIR/../lib/managed_files.sh"
# shellcheck source=../lib/quality_pack.sh
. "$SCRIPT_DIR/../lib/quality_pack.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "managed file sync" perl
bash "$SCRIPT_DIR/../ci/validate_config.sh" --scope project "${1:-}"

wp_plugin_base_load_config "${1:-}"
wp_plugin_base_require_vars FOUNDATION_RELEASE_SOURCE_PROVIDER FOUNDATION_RELEASE_SOURCE_REFERENCE FOUNDATION_RELEASE_SOURCE_API_BASE FOUNDATION_VERSION PLUGIN_NAME PLUGIN_SLUG MAIN_PLUGIN_FILE README_FILE ZIP_FILE PHP_VERSION NODE_VERSION
CODEOWNERS_REVIEWERS="${CODEOWNERS_REVIEWERS:-}"
WORDPRESS_QUALITY_PACK_ENABLED="${WORDPRESS_QUALITY_PACK_ENABLED:-false}"
WORDPRESS_SECURITY_PACK_ENABLED="${WORDPRESS_SECURITY_PACK_ENABLED:-false}"
GITHUB_RELEASE_UPDATER_ENABLED="${GITHUB_RELEASE_UPDATER_ENABLED:-false}"
GITHUB_RELEASE_UPDATER_REPO_URL="${GITHUB_RELEASE_UPDATER_REPO_URL:-}"
PLUGIN_RUNTIME_UPDATE_PROVIDER="${PLUGIN_RUNTIME_UPDATE_PROVIDER:-none}"
REST_OPERATIONS_PACK_ENABLED="${REST_OPERATIONS_PACK_ENABLED:-false}"
ADMIN_UI_PACK_ENABLED="${ADMIN_UI_PACK_ENABLED:-false}"
RUNTIME_UPDATE_PACK_ENABLED=false
if [ "$PLUGIN_RUNTIME_UPDATE_PROVIDER" != "none" ] || wp_plugin_base_is_true "$GITHUB_RELEASE_UPDATER_ENABLED"; then
  RUNTIME_UPDATE_PACK_ENABLED=true
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

  export FOUNDATION_REPOSITORY FOUNDATION_RELEASE_SOURCE_PROVIDER FOUNDATION_RELEASE_SOURCE_REFERENCE FOUNDATION_RELEASE_SOURCE_API_BASE FOUNDATION_VERSION PRODUCTION_ENVIRONMENT CODEOWNERS_REVIEWERS
  export PLUGIN_NAME PLUGIN_SLUG MAIN_PLUGIN_FILE README_FILE ZIP_FILE PHP_VERSION NODE_VERSION VERSION_CONSTANT_NAME DISTIGNORE_FILE
  export WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE GITHUB_RELEASE_UPDATER_REPO_URL PLUGIN_RUNTIME_UPDATE_PROVIDER PLUGIN_RUNTIME_UPDATE_SOURCE_URL AUTOMATION_PROVIDER REST_API_NAMESPACE REST_ABILITIES_ENABLED ADMIN_UI_EXPERIMENTAL_DATAVIEWS
  perl \
    -0pe 's~__FOUNDATION_REPOSITORY__~$ENV{FOUNDATION_REPOSITORY}~ge; s~__FOUNDATION_RELEASE_SOURCE_PROVIDER__~$ENV{FOUNDATION_RELEASE_SOURCE_PROVIDER}~ge; s~__FOUNDATION_RELEASE_SOURCE_REFERENCE__~$ENV{FOUNDATION_RELEASE_SOURCE_REFERENCE}~ge; s~__FOUNDATION_RELEASE_SOURCE_API_BASE__~$ENV{FOUNDATION_RELEASE_SOURCE_API_BASE}~ge; s~__FOUNDATION_VERSION__~$ENV{FOUNDATION_VERSION}~ge; s~__PRODUCTION_ENVIRONMENT__~$ENV{PRODUCTION_ENVIRONMENT}~ge; s~__CODEOWNERS_REVIEWERS__~$ENV{CODEOWNERS_REVIEWERS}~ge; s~__PLUGIN_NAME__~$ENV{PLUGIN_NAME}~ge; s~__PLUGIN_SLUG__~$ENV{PLUGIN_SLUG}~ge; s~__MAIN_PLUGIN_FILE__~$ENV{MAIN_PLUGIN_FILE}~ge; s~__README_FILE__~$ENV{README_FILE}~ge; s~__ZIP_FILE__~$ENV{ZIP_FILE}~ge; s~__PHP_VERSION__~$ENV{PHP_VERSION}~ge; s~__NODE_VERSION__~$ENV{NODE_VERSION}~ge; s~__VERSION_CONSTANT_NAME__~$ENV{VERSION_CONSTANT_NAME}~ge; s~__DISTIGNORE_FILE__~$ENV{DISTIGNORE_FILE}~ge; s~__WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE__~$ENV{WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE}~ge; s~__GITHUB_RELEASE_UPDATER_REPO_URL__~$ENV{GITHUB_RELEASE_UPDATER_REPO_URL}~ge; s~__PLUGIN_RUNTIME_UPDATE_PROVIDER__~$ENV{PLUGIN_RUNTIME_UPDATE_PROVIDER}~ge; s~__PLUGIN_RUNTIME_UPDATE_SOURCE_URL__~$ENV{PLUGIN_RUNTIME_UPDATE_SOURCE_URL}~ge; s~__AUTOMATION_PROVIDER__~$ENV{AUTOMATION_PROVIDER}~ge; s~__REST_API_NAMESPACE__~$ENV{REST_API_NAMESPACE}~ge; s~__REST_ABILITIES_ENABLED__~$ENV{REST_ABILITIES_ENABLED}~ge; s~__ADMIN_UI_EXPERIMENTAL_DATAVIEWS__~$ENV{ADMIN_UI_EXPERIMENTAL_DATAVIEWS}~ge' \
    "$source_file" > "$destination_file"
}

seed_template_once() {
  local source_file="$1"
  local destination_file="$2"

  if [ -e "$destination_file" ]; then
    return 0
  fi

  render_template "$source_file" "$destination_file"
}

warn_quality_pack_bootstrap_migration_risk() {
  local managed_bootstrap_template="$TEMPLATE_DIR/quality-pack/tests/bootstrap.php"
  local managed_bootstrap_path="$ROOT_DIR/tests/bootstrap.php"
  local child_bootstrap_path="$ROOT_DIR/tests/wp-plugin-base/bootstrap-child.php"
  local rendered_template

  if ! wp_plugin_base_quality_pack_phpunit_bridge_enabled && ! wp_plugin_base_quality_pack_is_full_enabled; then
    return 0
  fi

  if [ ! -f "$managed_bootstrap_template" ] || [ ! -f "$managed_bootstrap_path" ]; then
    return 0
  fi

  rendered_template="$(mktemp)"
  render_template "$managed_bootstrap_template" "$rendered_template"

  if ! cmp -s "$managed_bootstrap_path" "$rendered_template" && [ ! -s "$child_bootstrap_path" ]; then
    {
      echo "Warning: tests/bootstrap.php is managed by wp-plugin-base and was customized in this repository."
      echo "Warning: Child-specific PHPUnit preloads and support-class requires should live in tests/wp-plugin-base/bootstrap-child.php."
      echo "Warning: Sync may overwrite tests/bootstrap.php and break post-sync CI until those preloads are moved."
      echo "Warning: See docs/existing-project-migration.md#phpunit-bootstrap-migration and docs/troubleshooting.md#post-sync-phpunit-bootstrap-regressions."
    } >&2
  fi

  rm -f "$rendered_template"
}

remove_stale_managed_aliases() {
  if [ "$DISTIGNORE_FILE" != ".distignore" ]; then
    rm -f "$ROOT_DIR/.distignore"
  fi

  if [ "$WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE" != ".wp-plugin-base-security-suppressions.json" ]; then
    rm -f "$ROOT_DIR/.wp-plugin-base-security-suppressions.json"
  fi
}

remove_stale_automation_managed_files() {
  case "${AUTOMATION_PROVIDER:-github}" in
    gitlab)
      rm -f \
        "$ROOT_DIR/.github/dependabot.yml" \
        "$ROOT_DIR/.github/CODEOWNERS" \
        "$ROOT_DIR/.github/workflows/ci.yml" \
        "$ROOT_DIR/.github/workflows/finalize-release.yml" \
        "$ROOT_DIR/.github/workflows/prepare-release.yml" \
        "$ROOT_DIR/.github/workflows/release.yml" \
        "$ROOT_DIR/.github/workflows/update-foundation.yml" \
        "$ROOT_DIR/.github/workflows/simulate-release.yml" \
        "$ROOT_DIR/.github/workflows/woocommerce-status.yml"
      find "$ROOT_DIR/.github/workflows" -type d -empty -delete 2>/dev/null || true
      find "$ROOT_DIR/.github" -type d -empty -delete 2>/dev/null || true
      ;;
    *)
      rm -f "$ROOT_DIR/.gitlab-ci.yml" "$ROOT_DIR/.gitlab/CODEOWNERS"
      find "$ROOT_DIR/.gitlab" -type d -empty -delete 2>/dev/null || true
      ;;
  esac
}

while IFS=$'\t' read -r source_file destination_path; do
  [ -n "$source_file" ] || continue
  if [ "$destination_path" = "$WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE" ] && [ -f "$ROOT_DIR/$destination_path" ]; then
    continue
  fi
  render_template "$source_file" "$ROOT_DIR/$destination_path"
done < <(wp_plugin_base_print_base_managed_template_pairs "$TEMPLATE_DIR")

remove_stale_managed_aliases
remove_stale_automation_managed_files

if [ -z "$CODEOWNERS_REVIEWERS" ]; then
  rm -f "$ROOT_DIR/.github/CODEOWNERS"
  rm -f "$ROOT_DIR/.gitlab/CODEOWNERS"
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
REST_OPERATIONS_PACK_TEMPLATE_DIR="$TEMPLATE_DIR/rest-operations-pack"
REST_OPERATIONS_SEED_TEMPLATE_DIR="$TEMPLATE_DIR/rest-operations-pack-seed"
ADMIN_UI_PACK_TEMPLATE_DIR="$TEMPLATE_DIR/admin-ui-pack"
ADMIN_UI_SEED_COMMON_TEMPLATE_DIR="$TEMPLATE_DIR/admin-ui-pack-seed-common"
ADMIN_UI_SEED_BASIC_TEMPLATE_DIR="$TEMPLATE_DIR/admin-ui-pack-seed-basic"
ADMIN_UI_SEED_DATAVIEWS_TEMPLATE_DIR="$TEMPLATE_DIR/admin-ui-pack-seed-dataviews"

warn_quality_pack_bootstrap_migration_risk

if [ -d "$QUALITY_PACK_TEMPLATE_DIR" ]; then
  rm -f "$ROOT_DIR/tests/test-plugin-loads.php"
  rm -f "$ROOT_DIR/tests/PluginLoadsTest.php"

  while IFS= read -r template_file; do
    [ -n "$template_file" ] || continue
    relative_path="${template_file#"$QUALITY_PACK_TEMPLATE_DIR"/}"
    destination_path="$ROOT_DIR/$relative_path"
    mode="$(wp_plugin_base_quality_pack_template_mode "$relative_path" || true)"

    if [ -n "$mode" ]; then
      render_template "$template_file" "$destination_path"
      continue
    fi

    rm -f "$destination_path"
  done < <(find "$QUALITY_PACK_TEMPLATE_DIR" -type f | sort)

  if ! wp_plugin_base_quality_pack_is_full_enabled && ! wp_plugin_base_quality_pack_phpunit_bridge_enabled; then
    find "$ROOT_DIR/.wp-plugin-base-quality-pack" -type d -empty -delete 2>/dev/null || true
    find "$ROOT_DIR/bin" -type d -empty -delete 2>/dev/null || true
    find "$ROOT_DIR/tests" -type d -empty -delete 2>/dev/null || true
  fi
fi

if [ -d "$TEMPLATE_DIR/quality-pack-seed" ]; then
  while IFS= read -r template_file; do
    [ -n "$template_file" ] || continue
    relative_path="${template_file#"$TEMPLATE_DIR/quality-pack-seed/"}"
    destination_path="$ROOT_DIR/$relative_path"
    mode="$(wp_plugin_base_quality_pack_seed_mode "$relative_path" || true)"

    if [ -n "$mode" ]; then
      seed_template_once "$template_file" "$destination_path"
      continue
    fi

    rm -f "$destination_path"
  done < <(find "$TEMPLATE_DIR/quality-pack-seed" -type f | sort)
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

    if wp_plugin_base_is_true "$RUNTIME_UPDATE_PACK_ENABLED"; then
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

  if ! wp_plugin_base_is_true "$RUNTIME_UPDATE_PACK_ENABLED"; then
    find "$ROOT_DIR/lib/wp-plugin-base/plugin-update-checker" -type d -empty -delete 2>/dev/null || true
    find "$ROOT_DIR/lib/wp-plugin-base" -type d -empty -delete 2>/dev/null || true
    find "$ROOT_DIR/lib" -type d -empty -delete 2>/dev/null || true
  fi
fi

if [ -d "$REST_OPERATIONS_PACK_TEMPLATE_DIR" ]; then
  while IFS= read -r template_file; do
    [ -n "$template_file" ] || continue
    relative_path="${template_file#"$REST_OPERATIONS_PACK_TEMPLATE_DIR"/}"
    destination_path="$ROOT_DIR/$relative_path"

    if wp_plugin_base_is_true "$REST_OPERATIONS_PACK_ENABLED"; then
      render_template "$template_file" "$destination_path"
      continue
    fi

    rm -f "$destination_path"
  done < <(find "$REST_OPERATIONS_PACK_TEMPLATE_DIR" -type f | sort)
fi

if [ -d "$REST_OPERATIONS_SEED_TEMPLATE_DIR" ] && wp_plugin_base_is_true "$REST_OPERATIONS_PACK_ENABLED"; then
  while IFS= read -r template_file; do
    [ -n "$template_file" ] || continue
    relative_path="${template_file#"$REST_OPERATIONS_SEED_TEMPLATE_DIR"/}"
    destination_path="$ROOT_DIR/$relative_path"
    seed_template_once "$template_file" "$destination_path"
  done < <(find "$REST_OPERATIONS_SEED_TEMPLATE_DIR" -type f | sort)
fi

if [ -d "$ADMIN_UI_PACK_TEMPLATE_DIR" ]; then
  while IFS= read -r template_file; do
    [ -n "$template_file" ] || continue
    relative_path="${template_file#"$ADMIN_UI_PACK_TEMPLATE_DIR"/}"
    destination_path="$ROOT_DIR/$relative_path"

    if wp_plugin_base_is_true "$ADMIN_UI_PACK_ENABLED"; then
      render_template "$template_file" "$destination_path"
      continue
    fi

    rm -f "$destination_path"
  done < <(find "$ADMIN_UI_PACK_TEMPLATE_DIR" -type f | sort)
fi

if [ -d "$ADMIN_UI_SEED_COMMON_TEMPLATE_DIR" ] && wp_plugin_base_is_true "$ADMIN_UI_PACK_ENABLED"; then
  while IFS= read -r template_file; do
    [ -n "$template_file" ] || continue
    relative_path="${template_file#"$ADMIN_UI_SEED_COMMON_TEMPLATE_DIR"/}"
    destination_path="$ROOT_DIR/$relative_path"
    seed_template_once "$template_file" "$destination_path"
  done < <(find "$ADMIN_UI_SEED_COMMON_TEMPLATE_DIR" -type f | sort)
fi

if wp_plugin_base_is_true "$ADMIN_UI_PACK_ENABLED"; then
  if [ "${ADMIN_UI_STARTER:-basic}" = "dataviews" ]; then
    ADMIN_UI_VARIANT_TEMPLATE_DIR="$ADMIN_UI_SEED_DATAVIEWS_TEMPLATE_DIR"
  else
    ADMIN_UI_VARIANT_TEMPLATE_DIR="$ADMIN_UI_SEED_BASIC_TEMPLATE_DIR"
  fi

  if [ -d "$ADMIN_UI_VARIANT_TEMPLATE_DIR" ]; then
    while IFS= read -r template_file; do
      [ -n "$template_file" ] || continue
      relative_path="${template_file#"$ADMIN_UI_VARIANT_TEMPLATE_DIR"/}"
      destination_path="$ROOT_DIR/$relative_path"
      seed_template_once "$template_file" "$destination_path"
    done < <(find "$ADMIN_UI_VARIANT_TEMPLATE_DIR" -type f | sort)
  fi
fi

echo "Synchronized managed project files."
