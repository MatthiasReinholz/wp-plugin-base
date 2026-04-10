#!/usr/bin/env bash

set -euo pipefail

wp_plugin_base_child_template_dir() {
  printf '%s/.wp-plugin-base/templates/child\n' "$ROOT_DIR"
}

wp_plugin_base_print_base_managed_template_pairs() {
  local template_dir="${1:-$(wp_plugin_base_child_template_dir)}"
  local relative_path

  for relative_path in \
    ".editorconfig" \
    ".gitattributes" \
    ".github/dependabot.yml" \
    ".github/workflows/ci.yml" \
    ".github/workflows/finalize-release.yml" \
    ".github/workflows/prepare-release.yml" \
    ".github/workflows/release.yml" \
    ".github/workflows/update-foundation.yml" \
    ".gitignore" \
    "CONTRIBUTING.md" \
    "SECURITY.md" \
    "uninstall.php.example"
  do
    printf '%s\t%s\n' "$template_dir/$relative_path" "$relative_path"
  done

  printf '%s\t%s\n' "$template_dir/.distignore" "$DISTIGNORE_FILE"

  if [ -n "${CODEOWNERS_REVIEWERS:-}" ]; then
    printf '%s\t%s\n' "$template_dir/.github/CODEOWNERS" ".github/CODEOWNERS"
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

  wp_plugin_base_print_base_managed_template_pairs "$template_dir"

  if wp_plugin_base_is_true "${WORDPRESS_QUALITY_PACK_ENABLED:-false}"; then
    wp_plugin_base_print_optional_managed_template_pairs "quality-pack" "$template_dir"
  fi

  if wp_plugin_base_is_true "${WORDPRESS_SECURITY_PACK_ENABLED:-false}"; then
    wp_plugin_base_print_optional_managed_template_pairs "security-pack" "$template_dir"
  fi

  if wp_plugin_base_is_true "${WOOCOMMERCE_QIT_ENABLED:-false}"; then
    wp_plugin_base_print_optional_managed_template_pairs "qit-pack" "$template_dir"
  fi

  if wp_plugin_base_is_true "${SIMULATE_RELEASE_WORKFLOW_ENABLED:-false}"; then
    printf '%s\t%s\n' "$template_dir/.github/workflows/simulate-release.yml" ".github/workflows/simulate-release.yml"
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
