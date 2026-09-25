#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"
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
wp_plugin_base_require_commands "GitLab published artifact recovery" curl jq python3 cosign
wp_plugin_base_load_config "$CONFIG_OVERRIDE"
wp_plugin_base_require_managed_automation "release and deployment"
wp_plugin_base_require_vars CI_PROJECT_PATH PLUGIN_SLUG ZIP_FILE
wp_plugin_base_package_lock "$0" "$@"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
api_base="${CI_API_V4_URL:-$AUTOMATION_API_BASE}"
project_id="$(wp_plugin_base_provider_gitlab_project_id "$CI_PROJECT_PATH")"
header_name=PRIVATE-TOKEN
token="${GITLAB_TOKEN:-${CI_JOB_TOKEN:-}}"
if [ -z "$token" ]; then
  echo "GITLAB_TOKEN or CI_JOB_TOKEN is required." >&2
  exit 1
fi
if [ -z "${GITLAB_TOKEN:-}" ]; then header_name=JOB-TOKEN; fi
(umask 077; printf '%s: %s\n' "$header_name" "$token" > "$WORK_DIR/header")
unset token

download_asset() {
  curl --fail --silent --show-error --connect-timeout 10 --max-time 120 \
    --header "@$WORK_DIR/header" "$1" --output "$2"
  test -s "$2"
}

status="$(curl --silent --show-error --connect-timeout 10 --max-time 120 \
  --header "@$WORK_DIR/header" --output "$WORK_DIR/release.json" --write-out '%{http_code}' \
  "$api_base/projects/$project_id/releases/$VERSION")"
case "$status" in
  200) ;;
  404) exit 3 ;; # No host release: the caller may build and publish the first one.
  *) echo "GitLab release lookup failed (HTTP $status)." >&2; exit 1 ;;
esac
jq -e --arg version "$VERSION" '.tag_name == $version and (.upcoming_release // false) == false' "$WORK_DIR/release.json" >/dev/null
for asset_name in "$ZIP_FILE" "$ZIP_FILE.sbom.cdx.json" "$ZIP_FILE.sigstore.json"; do
  url="$(jq -er --arg name "$asset_name" '
    [.assets.links[] | select(.name == $name)]
    | if length == 1 then .[0].url else error("Release requires exactly one matching asset") end
  ' "$WORK_DIR/release.json")"
  url="$(wp_plugin_base_provider_gitlab_asset_api_url "$api_base" "$CI_PROJECT_PATH" "$url")"
  download_asset "$url" "$WORK_DIR/$asset_name"
done
bash "$SCRIPT_DIR/verify_sigstore_bundle.sh" "$CI_PROJECT_PATH" "$WORK_DIR/$ZIP_FILE" \
  "$WORK_DIR/$ZIP_FILE.sigstore.json" plugin gitlab-release "$api_base" "" "$VERSION" "${DEFAULT_BRANCH:-main}"
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
echo "Restored verified published GitLab artifacts for channel retry: $VERSION"
