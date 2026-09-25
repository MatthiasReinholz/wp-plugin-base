#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"
# shellcheck source=../lib/package_generation.sh
. "$SCRIPT_DIR/../lib/package_generation.sh"

VERSION="${1:-}"
CONFIG_OVERRIDE="${2:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 <x.y.z> [config-path]" >&2
  exit 1
fi
wp_plugin_base_require_commands "published artifact recovery" gh jq python3 cosign
wp_plugin_base_load_config "$CONFIG_OVERRIDE"
wp_plugin_base_require_managed_automation "release and deployment"
wp_plugin_base_require_vars GITHUB_REPOSITORY PLUGIN_SLUG ZIP_FILE
wp_plugin_base_package_lock "$0" "$@"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
for asset_name in "$ZIP_FILE" "$ZIP_FILE.sbom.cdx.json" "$ZIP_FILE.sigstore.json"; do
  gh release download "$VERSION" --repo "$GITHUB_REPOSITORY" --dir "$WORK_DIR" --pattern "$asset_name"
done
bash "$SCRIPT_DIR/verify_github_release_assets.sh" "$VERSION" false \
  "$WORK_DIR/$ZIP_FILE" "$WORK_DIR/$ZIP_FILE.sbom.cdx.json" "$WORK_DIR/$ZIP_FILE.sigstore.json"
bash "$SCRIPT_DIR/verify_sigstore_bundle.sh" "$GITHUB_REPOSITORY" \
  "$WORK_DIR/$ZIP_FILE" "$WORK_DIR/$ZIP_FILE.sigstore.json" plugin github-release https://api.github.com "" "" "${DEFAULT_BRANCH:-main}"

# Validate archive paths before extraction, even though the payload is signed.
# Distribution only consumes files under the configured plugin root.
python3 "$SCRIPT_DIR/extract_release_package.py" "$WORK_DIR/$ZIP_FILE" "$WORK_DIR/package" "$PLUGIN_SLUG"

GENERATION_DIR="$(python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" create "$ROOT_DIR" "$PLUGIN_SLUG" "$ZIP_FILE")"
trap 'rm -rf "$WORK_DIR"; if [ -n "${GENERATION_DIR:-}" ]; then python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" discard "$ROOT_DIR" "$GENERATION_DIR" || true; fi' EXIT
mv "$WORK_DIR/package" "$GENERATION_DIR/package"
for asset_name in "$ZIP_FILE" "$ZIP_FILE.sbom.cdx.json" "$ZIP_FILE.sigstore.json"; do
  mv "$WORK_DIR/$asset_name" "$GENERATION_DIR/$asset_name"
done
for required_file in "$MAIN_PLUGIN_FILE" "$README_FILE"; do
  if [ ! -f "$GENERATION_DIR/package/$PLUGIN_SLUG/$required_file" ]; then
    echo "Published package is missing required file: $required_file" >&2
    exit 1
  fi
done
python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" recover "$ROOT_DIR" "$GENERATION_DIR" "$PLUGIN_SLUG" "$ZIP_FILE"
GENERATION_DIR=""
echo "Restored verified published artifacts for channel retry: $VERSION"
