#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

VERSION="${1:-}"
CONFIG_OVERRIDE="${2:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 <x.y.z> [config-path]" >&2
  exit 1
fi
wp_plugin_base_require_commands "published artifact recovery" gh jq python3 cosign
wp_plugin_base_load_config "$CONFIG_OVERRIDE"
wp_plugin_base_require_vars GITHUB_REPOSITORY PLUGIN_SLUG ZIP_FILE

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
for asset_name in "$ZIP_FILE" "$ZIP_FILE.sbom.cdx.json" "$ZIP_FILE.sigstore.json"; do
  gh release download "$VERSION" --repo "$GITHUB_REPOSITORY" --dir "$WORK_DIR" --pattern "$asset_name"
done
bash "$SCRIPT_DIR/verify_github_release_assets.sh" "$VERSION" false \
  "$WORK_DIR/$ZIP_FILE" "$WORK_DIR/$ZIP_FILE.sbom.cdx.json" "$WORK_DIR/$ZIP_FILE.sigstore.json"
bash "$SCRIPT_DIR/verify_sigstore_bundle.sh" "$GITHUB_REPOSITORY" \
  "$WORK_DIR/$ZIP_FILE" "$WORK_DIR/$ZIP_FILE.sigstore.json" plugin github-release https://api.github.com

# Validate archive paths before extraction, even though the payload is signed.
# Distribution only consumes files under the configured plugin root.
python3 "$SCRIPT_DIR/extract_release_package.py" "$WORK_DIR/$ZIP_FILE" "$WORK_DIR/package" "$PLUGIN_SLUG"

mkdir -p "$ROOT_DIR/dist/package"
rm -rf "$ROOT_DIR/dist/package/$PLUGIN_SLUG"
mv "$WORK_DIR/package/$PLUGIN_SLUG" "$ROOT_DIR/dist/package/$PLUGIN_SLUG"
cp "$WORK_DIR/$ZIP_FILE" "$WORK_DIR/$ZIP_FILE.sbom.cdx.json" "$WORK_DIR/$ZIP_FILE.sigstore.json" "$ROOT_DIR/dist/"
echo "Restored verified published artifacts for channel retry: $VERSION"
