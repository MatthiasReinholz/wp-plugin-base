#!/usr/bin/env bash

set -euo pipefail

_wp_plugin_base_managed_files_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=quality_pack.sh
. "$_wp_plugin_base_managed_files_lib_dir/quality_pack.sh"

wp_plugin_base_child_template_dir() {
  printf '%s/.wp-plugin-base/templates/child\n' "$ROOT_DIR" || return 1
}

_wp_plugin_base_collect_base_managed_template_pairs() {
  local template_dir="${1:-$ROOT_DIR/.wp-plugin-base/templates/child}"
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
    printf '%s\t%s\n' "$template_dir/$relative_path" "$relative_path" || return 1
  done

  case "$automation_provider" in
    gitlab)
      printf '%s\t%s\n' "$template_dir/.gitlab-ci.yml" ".gitlab-ci.yml" || return 1
      ;;
    *)
      for relative_path in \
        ".github/dependabot.yml" \
        ".github/workflows/ci.yml" \
        ".github/workflows/finalize-release.yml" \
        ".github/workflows/prepare-release.yml" \
        ".github/workflows/publish-tag-release.yml" \
        ".github/workflows/release.yml" \
        ".github/workflows/update-foundation.yml"
      do
        printf '%s\t%s\n' "$template_dir/$relative_path" "$relative_path" || return 1
      done
      ;;
  esac

  printf '%s\t%s\n' "$template_dir/.distignore" "$DISTIGNORE_FILE" || return 1

  if [ -n "${CODEOWNERS_REVIEWERS:-}" ]; then
    case "$automation_provider" in
      gitlab)
        printf '%s\t%s\n' "$template_dir/.gitlab/CODEOWNERS" ".gitlab/CODEOWNERS" || return 1
        ;;
      *)
        printf '%s\t%s\n' "$template_dir/.github/CODEOWNERS" ".github/CODEOWNERS" || return 1
        ;;
    esac
  fi

}

_wp_plugin_base_collect_optional_managed_template_pairs() {
  local pack_name="$1"
  local template_dir="${2:-$ROOT_DIR/.wp-plugin-base/templates/child}"
  local pack_dir="$template_dir/$pack_name"
  local template_file=""
  local relative_path=""
  local template_files=""

  if [ ! -d "$pack_dir" ]; then
    return 0
  fi

  template_files="$(find "$pack_dir" -type f | sort)" || return 1
  while IFS= read -r template_file; do
    [ -n "$template_file" ] || continue
    relative_path="${template_file#"$pack_dir"/}"
    printf '%s\t%s\n' "$template_file" "$relative_path" || return 1
  done <<< "$template_files"
}

_wp_plugin_base_collect_managed_template_pairs() {
  local template_dir="${1:-$ROOT_DIR/.wp-plugin-base/templates/child}"
  local quality_pack_dir="$template_dir/quality-pack"
  local template_file=""
  local relative_path=""
  local template_files=""

  _wp_plugin_base_collect_base_managed_template_pairs "$template_dir" || return 1

  if [ -d "$quality_pack_dir" ]; then
    template_files="$(find "$quality_pack_dir" -type f | sort)" || return 1
    while IFS= read -r template_file; do
      [ -n "$template_file" ] || continue
      relative_path="${template_file#"$quality_pack_dir"/}"
      if wp_plugin_base_quality_pack_template_mode "$relative_path" >/dev/null 2>&1; then
        printf '%s\t%s\n' "$template_file" "$relative_path" || return 1
      fi
    done <<< "$template_files"
  fi

  if wp_plugin_base_is_true "${WORDPRESS_SECURITY_PACK_ENABLED:-false}"; then
    _wp_plugin_base_collect_optional_managed_template_pairs "security-pack" "$template_dir" || return 1
  fi

  if [ "${AUTOMATION_PROVIDER:-github}" = github ] && wp_plugin_base_is_true "${WOOCOMMERCE_QIT_ENABLED:-false}"; then
    _wp_plugin_base_collect_optional_managed_template_pairs "qit-pack" "$template_dir" || return 1
  fi

  if [ -n "${WOOCOMMERCE_COM_PRODUCT_ID:-}" ]; then
    if [ "${AUTOMATION_PROVIDER:-github}" = "github" ]; then
      printf '%s\t%s\n' "$template_dir/.github/workflows/woocommerce-status.yml" ".github/workflows/woocommerce-status.yml" || return 1
    fi
  fi

  if [ "${PLUGIN_RUNTIME_UPDATE_PROVIDER:-none}" != "none" ] || wp_plugin_base_is_true "${GITHUB_RELEASE_UPDATER_ENABLED:-false}"; then
    _wp_plugin_base_collect_optional_managed_template_pairs "github-release-updater-pack" "$template_dir" || return 1
  fi

  if wp_plugin_base_is_true "${REST_OPERATIONS_PACK_ENABLED:-false}"; then
    _wp_plugin_base_collect_optional_managed_template_pairs "rest-operations-pack" "$template_dir" || return 1
  fi

  if wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}"; then
    _wp_plugin_base_collect_optional_managed_template_pairs "admin-ui-pack" "$template_dir" || return 1
  fi

  if wp_plugin_base_is_true "${SIMULATE_RELEASE_WORKFLOW_ENABLED:-false}"; then
    if [ "${AUTOMATION_PROVIDER:-github}" = "github" ]; then
      printf '%s\t%s\n' "$template_dir/.github/workflows/simulate-release.yml" ".github/workflows/simulate-release.yml" || return 1
    fi
  fi
}

_wp_plugin_base_collect_managed_paths() {
  local template_file=""
  local destination_path=""
  local pairs=""

  pairs="$(wp_plugin_base_print_managed_template_pairs "$@")" || return 1
  while IFS=$'\t' read -r template_file destination_path; do
    [ -n "$destination_path" ] || continue
    printf '%s\n' "$destination_path" || return 1
  done <<< "$pairs"
}

_wp_plugin_base_collect_seed_template_pairs() {
  local pack_name="$1"
  local template_dir="${2:-$ROOT_DIR/.wp-plugin-base/templates/child}"
  local seed_dir="$template_dir/$pack_name"
  local template_file=""
  local relative_path=""
  local template_files=""

  if [ ! -d "$seed_dir" ]; then
    return 0
  fi

  template_files="$(find "$seed_dir" -type f | sort)" || return 1
  while IFS= read -r template_file; do
    [ -n "$template_file" ] || continue
    relative_path="${template_file#"$seed_dir"/}"
    printf '%s\t%s\n' "$template_file" "$relative_path" || return 1
  done <<< "$template_files"
}

_wp_plugin_base_collect_required_seed_template_pairs() {
  local template_dir="${1:-$ROOT_DIR/.wp-plugin-base/templates/child}"
  local quality_pack_seed_dir="$template_dir/quality-pack-seed"
  local template_file=""
  local relative_path=""
  local template_files=""

  if [ -f "$template_dir/AGENTS.md" ]; then
    printf '%s\t%s\n' "$template_dir/AGENTS.md" "AGENTS.md" || return 1
  fi

  if [ -f "$template_dir/.wp-plugin-base-security-suppressions.json" ]; then
    printf '%s\t%s\n' \
      "$template_dir/.wp-plugin-base-security-suppressions.json" \
      "$WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE" || return 1
  fi

  if wp_plugin_base_is_true "${REST_OPERATIONS_PACK_ENABLED:-false}"; then
    _wp_plugin_base_collect_seed_template_pairs "rest-operations-pack-seed" "$template_dir" || return 1
  fi

  if wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}"; then
    _wp_plugin_base_collect_seed_template_pairs "admin-ui-pack-seed-common" "$template_dir" || return 1

    if [ "${ADMIN_UI_STARTER:-basic}" = "dataviews" ]; then
      _wp_plugin_base_collect_seed_template_pairs "admin-ui-pack-seed-dataviews" "$template_dir" || return 1
    else
      _wp_plugin_base_collect_seed_template_pairs "admin-ui-pack-seed-basic" "$template_dir" || return 1
    fi
  fi

  if [ -d "$quality_pack_seed_dir" ]; then
    template_files="$(find "$quality_pack_seed_dir" -type f | sort)" || return 1
    while IFS= read -r template_file; do
      [ -n "$template_file" ] || continue
      relative_path="${template_file#"$quality_pack_seed_dir"/}"
      if wp_plugin_base_quality_pack_seed_mode "$relative_path" >/dev/null 2>&1; then
        printf '%s\t%s\n' "$template_file" "$relative_path" || return 1
      fi
    done <<< "$template_files"
  fi
}

_wp_plugin_base_collect_required_seed_paths() {
  local template_file=""
  local destination_path=""
  local pairs=""

  pairs="$(wp_plugin_base_print_required_seed_template_pairs "$@")" || return 1
  while IFS=$'\t' read -r template_file destination_path; do
    [ -n "$destination_path" ] || continue
    printf '%s\n' "$destination_path" || return 1
  done <<< "$pairs"
}

# The union is used only for managed cleanup. Keep all host/pack policy above so
# generation, validation, staging and removal cannot acquire different file lists.
_wp_plugin_base_collect_all_managed_paths() (
  local template_dir="${1:-$ROOT_DIR/.wp-plugin-base/templates/child}"
  WORDPRESS_QUALITY_PACK_ENABLED=true
  WORDPRESS_SECURITY_PACK_ENABLED=true
  WOOCOMMERCE_QIT_ENABLED=true
  WOOCOMMERCE_COM_PRODUCT_ID=1
  PLUGIN_RUNTIME_UPDATE_PROVIDER=github-release
  REST_OPERATIONS_PACK_ENABLED=true
  ADMIN_UI_PACK_ENABLED=true
  SIMULATE_RELEASE_WORKFLOW_ENABLED=true
  CODEOWNERS_REVIEWERS=@manifest
  local paths=""
  paths="$(
    for AUTOMATION_PROVIDER in github gitlab; do
      wp_plugin_base_print_managed_paths "$template_dir" || exit 1
    done
  )" || return 1
  sort -u <<< "$paths" || return 1
)

# Bash 3.2 can lose a printf row when a pipe write is interrupted. Build into a
# private regular file, check every producer, then publish through Ruby's bounded
# write loop. A generation/read failure never publishes a partial manifest.
_wp_plugin_base_emit_managed_manifest() (
  local manifest
  local unique=""
  if [ "${1:-}" = --unique ]; then
    unique=--unique
    shift
  fi
  manifest="$(mktemp)" || exit 1
  trap 'rm -f "$manifest"' EXIT
  if ! "$@" > "$manifest"; then
    echo "Cannot generate the managed file manifest." >&2
    exit 1
  fi
  ruby "$_wp_plugin_base_managed_files_lib_dir/managed_manifest_io.rb" "$manifest" "$unique"
)

wp_plugin_base_print_base_managed_template_pairs() {
  _wp_plugin_base_emit_managed_manifest _wp_plugin_base_collect_base_managed_template_pairs "$@"
}

wp_plugin_base_print_optional_managed_template_pairs() {
  _wp_plugin_base_emit_managed_manifest _wp_plugin_base_collect_optional_managed_template_pairs "$@"
}

wp_plugin_base_print_managed_template_pairs() {
  _wp_plugin_base_emit_managed_manifest _wp_plugin_base_collect_managed_template_pairs "$@"
}

wp_plugin_base_print_managed_paths() {
  _wp_plugin_base_emit_managed_manifest _wp_plugin_base_collect_managed_paths "$@"
}

wp_plugin_base_print_seed_template_pairs() {
  _wp_plugin_base_emit_managed_manifest _wp_plugin_base_collect_seed_template_pairs "$@"
}

wp_plugin_base_print_required_seed_template_pairs() {
  _wp_plugin_base_emit_managed_manifest _wp_plugin_base_collect_required_seed_template_pairs "$@"
}

wp_plugin_base_print_required_seed_paths() {
  _wp_plugin_base_emit_managed_manifest _wp_plugin_base_collect_required_seed_paths "$@"
}

wp_plugin_base_print_all_managed_paths() {
  _wp_plugin_base_emit_managed_manifest _wp_plugin_base_collect_all_managed_paths "$@"
}
