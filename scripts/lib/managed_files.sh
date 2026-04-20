#!/usr/bin/env bash

set -euo pipefail

_wp_plugin_base_managed_files_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=quality_pack.sh
. "$_wp_plugin_base_managed_files_lib_dir/quality_pack.sh"

wp_plugin_base_child_template_dir() {
  printf '%s/.wp-plugin-base/templates/child\n' "$ROOT_DIR"
}

wp_plugin_base_print_base_managed_template_pairs() {
  local template_dir="${1:-$(wp_plugin_base_child_template_dir)}"
  local relative_path
  local automation_provider="${AUTOMATION_PROVIDER:-github}"

  for relative_path in \
    ".editorconfig" \
    ".gitattributes" \
    ".gitignore" \
    "CONTRIBUTING.md" \
    "SECURITY.md" \
    "uninstall.php.example"
  do
    printf '%s\t%s\n' "$template_dir/$relative_path" "$relative_path"
  done

  case "$automation_provider" in
    gitlab)
      printf '%s\t%s\n' "$template_dir/.gitlab-ci.yml" ".gitlab-ci.yml"
      ;;
    *)
      for relative_path in \
        ".github/dependabot.yml" \
        ".github/workflows/ci.yml" \
        ".github/workflows/finalize-release.yml" \
        ".github/workflows/prepare-release.yml" \
        ".github/workflows/release.yml" \
        ".github/workflows/update-foundation.yml"
      do
        printf '%s\t%s\n' "$template_dir/$relative_path" "$relative_path"
      done
      ;;
  esac

  printf '%s\t%s\n' "$template_dir/.distignore" "$DISTIGNORE_FILE"

  if [ -n "${CODEOWNERS_REVIEWERS:-}" ]; then
    case "$automation_provider" in
      gitlab)
        printf '%s\t%s\n' "$template_dir/.gitlab/CODEOWNERS" ".gitlab/CODEOWNERS"
        ;;
      *)
        printf '%s\t%s\n' "$template_dir/.github/CODEOWNERS" ".github/CODEOWNERS"
        ;;
    esac
  fi

  printf '%s\t%s\n' \
    "$template_dir/.wp-plugin-base-security-suppressions.json" \
    "$WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE"
}

wp_plugin_base_print_optional_managed_template_pairs() {
  local pack_name="$1"
  local template_dir="${2:-$(wp_plugin_base_child_template_dir)}"
  local pack_dir="$template_dir/$pack_name"
  local template_file=""
  local relative_path=""

  if [ ! -d "$pack_dir" ]; then
    return 0
  fi

  while IFS= read -r template_file; do
    [ -n "$template_file" ] || continue
    relative_path="${template_file#"$pack_dir"/}"
    printf '%s\t%s\n' "$template_file" "$relative_path"
  done < <(find "$pack_dir" -type f | sort)
}

wp_plugin_base_print_managed_template_pairs() {
  local template_dir="${1:-$(wp_plugin_base_child_template_dir)}"
  local quality_pack_dir="$template_dir/quality-pack"
  local template_file=""
  local relative_path=""

  wp_plugin_base_print_base_managed_template_pairs "$template_dir"

  if [ -d "$quality_pack_dir" ]; then
    while IFS= read -r template_file; do
      [ -n "$template_file" ] || continue
      relative_path="${template_file#"$quality_pack_dir"/}"
      if wp_plugin_base_quality_pack_template_mode "$relative_path" >/dev/null 2>&1; then
        printf '%s\t%s\n' "$template_file" "$relative_path"
      fi
    done < <(find "$quality_pack_dir" -type f | sort)
  fi

  if wp_plugin_base_is_true "${WORDPRESS_SECURITY_PACK_ENABLED:-false}"; then
    wp_plugin_base_print_optional_managed_template_pairs "security-pack" "$template_dir"
  fi

  if wp_plugin_base_is_true "${WOOCOMMERCE_QIT_ENABLED:-false}"; then
    wp_plugin_base_print_optional_managed_template_pairs "qit-pack" "$template_dir"
  fi

  if [ -n "${WOOCOMMERCE_COM_PRODUCT_ID:-}" ]; then
    if [ "${AUTOMATION_PROVIDER:-github}" = "github" ]; then
      printf '%s\t%s\n' "$template_dir/.github/workflows/woocommerce-status.yml" ".github/workflows/woocommerce-status.yml"
    fi
  fi

  if [ "${PLUGIN_RUNTIME_UPDATE_PROVIDER:-none}" != "none" ] || wp_plugin_base_is_true "${GITHUB_RELEASE_UPDATER_ENABLED:-false}"; then
    wp_plugin_base_print_optional_managed_template_pairs "github-release-updater-pack" "$template_dir"
  fi

  if wp_plugin_base_is_true "${REST_OPERATIONS_PACK_ENABLED:-false}"; then
    wp_plugin_base_print_optional_managed_template_pairs "rest-operations-pack" "$template_dir"
  fi

  if wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}"; then
    wp_plugin_base_print_optional_managed_template_pairs "admin-ui-pack" "$template_dir"
  fi

  if wp_plugin_base_is_true "${SIMULATE_RELEASE_WORKFLOW_ENABLED:-false}"; then
    if [ "${AUTOMATION_PROVIDER:-github}" = "github" ]; then
      printf '%s\t%s\n' "$template_dir/.github/workflows/simulate-release.yml" ".github/workflows/simulate-release.yml"
    fi
  fi
}

wp_plugin_base_print_managed_paths() {
  local template_file=""
  local destination_path=""

  while IFS=$'\t' read -r template_file destination_path; do
    [ -n "$destination_path" ] || continue
    printf '%s\n' "$destination_path"
  done < <(wp_plugin_base_print_managed_template_pairs "$@")
}

wp_plugin_base_print_seed_template_pairs() {
  local pack_name="$1"
  local template_dir="${2:-$(wp_plugin_base_child_template_dir)}"
  local seed_dir="$template_dir/$pack_name"
  local template_file=""
  local relative_path=""

  if [ ! -d "$seed_dir" ]; then
    return 0
  fi

  while IFS= read -r template_file; do
    [ -n "$template_file" ] || continue
    relative_path="${template_file#"$seed_dir"/}"
    printf '%s\t%s\n' "$template_file" "$relative_path"
  done < <(find "$seed_dir" -type f | sort)
}

wp_plugin_base_print_required_seed_template_pairs() {
  local template_dir="${1:-$(wp_plugin_base_child_template_dir)}"
  local quality_pack_seed_dir="$template_dir/quality-pack-seed"
  local template_file=""
  local relative_path=""

  if wp_plugin_base_is_true "${REST_OPERATIONS_PACK_ENABLED:-false}"; then
    wp_plugin_base_print_seed_template_pairs "rest-operations-pack-seed" "$template_dir"
  fi

  if wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}"; then
    wp_plugin_base_print_seed_template_pairs "admin-ui-pack-seed-common" "$template_dir"

    if [ "${ADMIN_UI_STARTER:-basic}" = "dataviews" ]; then
      wp_plugin_base_print_seed_template_pairs "admin-ui-pack-seed-dataviews" "$template_dir"
    else
      wp_plugin_base_print_seed_template_pairs "admin-ui-pack-seed-basic" "$template_dir"
    fi
  fi

  if [ -d "$quality_pack_seed_dir" ]; then
    while IFS= read -r template_file; do
      [ -n "$template_file" ] || continue
      relative_path="${template_file#"$quality_pack_seed_dir"/}"
      if wp_plugin_base_quality_pack_seed_mode "$relative_path" >/dev/null 2>&1; then
        printf '%s\t%s\n' "$template_file" "$relative_path"
      fi
    done < <(find "$quality_pack_seed_dir" -type f | sort)
  fi
}

wp_plugin_base_print_required_seed_paths() {
  local template_file=""
  local destination_path=""

  while IFS=$'\t' read -r template_file destination_path; do
    [ -n "$destination_path" ] || continue
    printf '%s\n' "$destination_path"
  done < <(wp_plugin_base_print_required_seed_template_pairs "$@")
}
