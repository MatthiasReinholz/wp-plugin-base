#!/usr/bin/env bash

# Config is loaded by the caller; keep the same contract in sync, validation,
# direct packaging, and staged-package verification.
_wp_plugin_base_build_outputs_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

wp_plugin_base_validate_build_inputs() {
  ROOT_DIR="$ROOT_DIR" BUILD_SCRIPT="${BUILD_SCRIPT:-}" \
    BUILD_OUTPUTS="${BUILD_OUTPUTS:-}" BUILD_OUTPUT_MANIFEST="${BUILD_OUTPUT_MANIFEST:-}" \
    PACKAGE_INCLUDE="${PACKAGE_INCLUDE:-}" MAIN_PLUGIN_FILE="${MAIN_PLUGIN_FILE:-}" \
    README_FILE="${README_FILE:-}" CONFIG_PATH="${CONFIG_PATH:-}" \
    DISTIGNORE_FILE="${DISTIGNORE_FILE:-.distignore}" \
    WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE="${WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE:-}" \
    ruby "$_wp_plugin_base_build_outputs_dir/build_outputs.rb" inputs
}

wp_plugin_base_validate_build_outputs() {
  local output_root="${1:-$ROOT_DIR}"
  ROOT_DIR="$ROOT_DIR" BUILD_SCRIPT="${BUILD_SCRIPT:-}" \
    BUILD_OUTPUTS="${BUILD_OUTPUTS:-}" BUILD_OUTPUT_MANIFEST="${BUILD_OUTPUT_MANIFEST:-}" \
    PACKAGE_INCLUDE="${PACKAGE_INCLUDE:-}" MAIN_PLUGIN_FILE="${MAIN_PLUGIN_FILE:-}" \
    README_FILE="${README_FILE:-}" CONFIG_PATH="${CONFIG_PATH:-}" \
    DISTIGNORE_FILE="${DISTIGNORE_FILE:-.distignore}" \
    WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE="${WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE:-}" \
    ruby "$_wp_plugin_base_build_outputs_dir/build_outputs.rb" outputs "$output_root"
}

# Run only after acquiring the cooperating package lock. The manifest parent is
# explicitly application-declared generated ownership, never inferred from includes.
wp_plugin_base_prepare_build_outputs() {
  ROOT_DIR="$ROOT_DIR" BUILD_SCRIPT="${BUILD_SCRIPT:-}" \
    BUILD_OUTPUTS="${BUILD_OUTPUTS:-}" BUILD_OUTPUT_MANIFEST="${BUILD_OUTPUT_MANIFEST:-}" \
    PACKAGE_INCLUDE="${PACKAGE_INCLUDE:-}" MAIN_PLUGIN_FILE="${MAIN_PLUGIN_FILE:-}" \
    README_FILE="${README_FILE:-}" CONFIG_PATH="${CONFIG_PATH:-}" \
    DISTIGNORE_FILE="${DISTIGNORE_FILE:-.distignore}" \
    WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE="${WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE:-}" \
    ruby "$_wp_plugin_base_build_outputs_dir/build_outputs.rb" prepare
}
