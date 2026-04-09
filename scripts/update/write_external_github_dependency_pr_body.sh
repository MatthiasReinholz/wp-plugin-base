#!/usr/bin/env bash

set -euo pipefail

OUTPUT_PATH="${1:-}"

if [ -z "$OUTPUT_PATH" ]; then
  echo "Usage: $0 <output-path>" >&2
  exit 1
fi

dependency_name="${WP_PLUGIN_BASE_DEPENDENCY_NAME:-}"
source_repository="${WP_PLUGIN_BASE_DEPENDENCY_SOURCE_REPOSITORY:-}"
current_version="${WP_PLUGIN_BASE_DEPENDENCY_CURRENT_VERSION:-}"
target_version="${WP_PLUGIN_BASE_DEPENDENCY_TARGET_VERSION:-}"
dependency_purpose="${WP_PLUGIN_BASE_DEPENDENCY_PURPOSE:-used by this repository}"
trust_checks="${WP_PLUGIN_BASE_DEPENDENCY_TRUST_CHECKS:-}"
trust_mode="${WP_PLUGIN_BASE_DEPENDENCY_TRUST_MODE:-metadata-only}"

if [ -z "$dependency_name" ] || [ -z "$source_repository" ] || [ -z "$current_version" ] || [ -z "$target_version" ]; then
  echo "WP_PLUGIN_BASE_DEPENDENCY_NAME, WP_PLUGIN_BASE_DEPENDENCY_SOURCE_REPOSITORY, WP_PLUGIN_BASE_DEPENDENCY_CURRENT_VERSION, and WP_PLUGIN_BASE_DEPENDENCY_TARGET_VERSION are required." >&2
  exit 1
fi

case "$trust_mode" in
  verified-provenance|metadata-only)
    ;;
  *)
    echo "Unsupported WP_PLUGIN_BASE_DEPENDENCY_TRUST_MODE: $trust_mode" >&2
    exit 1
    ;;
esac

{
  printf 'This PR updates the pinned `%s` version %s.\n\n' "$source_repository" "$dependency_purpose"
  printf 'Updated dependency version:\n'
  printf -- '- `%s` -> `%s`\n\n' "$current_version" "$target_version"
  printf 'Source repository:\n'
  printf -- '- `%s`\n\n' "$source_repository"
  printf 'Verification performed before proposing this update:\n'

  if [ -n "$trust_checks" ]; then
    while IFS= read -r check; do
      [ -n "$check" ] || continue
      printf -- '- %s\n' "$check"
    done <<EOF
$trust_checks
EOF
  else
    printf -- '- selected from GitHub release metadata for `%s`\n' "$source_repository"
  fi

  if [ "$trust_mode" = "metadata-only" ]; then
    printf '\nReviewer warning:\n'
    printf -- '- This update was selected from GitHub repository and release metadata, but the framework could not automatically verify first-party release authenticity beyond the configured trust checks.\n'
    printf -- '- Before merging, verify that `%s` `%s` is authentic and safe: review the upstream repository, tag, release notes, and release assets.\n' "$source_repository" "$target_version"
  else
    printf '\nTrust level:\n'
    printf -- '- first-party provenance for this dependency update was verified automatically.\n'
  fi
} > "$OUTPUT_PATH"
