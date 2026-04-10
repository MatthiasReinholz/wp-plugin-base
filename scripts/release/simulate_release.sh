#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "release simulation" git unzip

RELEASE_TYPE="${1:-}"
CUSTOM_VERSION="${2:-}"
CONFIG_OVERRIDE="${3:-}"

if [ -z "$RELEASE_TYPE" ]; then
  echo "Usage: $0 patch|minor|major|custom [version] [config-path]" >&2
  exit 1
fi

if [ "$RELEASE_TYPE" = "custom" ] && ! [[ "$CUSTOM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Custom simulations require an explicit x.y.z version." >&2
  exit 1
fi

if [ "$RELEASE_TYPE" != "custom" ] && [ -n "$CUSTOM_VERSION" ] && [[ "$CUSTOM_VERSION" =~ ^[A-Za-z./_-] ]]; then
  CONFIG_OVERRIDE="$CUSTOM_VERSION"
  CUSTOM_VERSION=""
fi

wp_plugin_base_load_config "$CONFIG_OVERRIDE"
wp_plugin_base_require_vars ZIP_FILE

SIM_WORKTREE="$(mktemp -d)"

cleanup() {
  git -C "$ROOT_DIR" worktree remove --force "$SIM_WORKTREE" >/dev/null 2>&1 || true
  rm -rf "$SIM_WORKTREE"
}
trap cleanup EXIT

HEAD_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD)"
git -C "$ROOT_DIR" worktree add --detach "$SIM_WORKTREE" "$HEAD_SHA" >/dev/null

if [ "$RELEASE_TYPE" = "custom" ]; then
  VERSION="$CUSTOM_VERSION"
else
  VERSION="$(
    WP_PLUGIN_BASE_ROOT="$SIM_WORKTREE" \
      bash "$SCRIPT_DIR/next_version.sh" "$RELEASE_TYPE" "$CONFIG_OVERRIDE"
  )"
fi

NOTES_FILE="$(mktemp)"
DIFF_FILE="$(mktemp)"
trap 'rm -f "$NOTES_FILE" "$DIFF_FILE"; cleanup' EXIT

WP_PLUGIN_BASE_ROOT="$SIM_WORKTREE" \
  bash "$SCRIPT_DIR/generate_release_notes.sh" "$VERSION" "$CONFIG_OVERRIDE" > "$NOTES_FILE"

WP_PLUGIN_BASE_ROOT="$SIM_WORKTREE" \
  bash "$SCRIPT_DIR/bump_version.sh" "$VERSION" "$CONFIG_OVERRIDE" >/dev/null

git -C "$SIM_WORKTREE" --no-pager diff --name-only > "$DIFF_FILE"

WP_PLUGIN_BASE_ROOT="$SIM_WORKTREE" \
  bash "$SCRIPT_DIR/../ci/build_zip.sh" "$CONFIG_OVERRIDE" >/dev/null

ZIP_PATH="$SIM_WORKTREE/dist/$ZIP_FILE"
if [ ! -f "$ZIP_PATH" ]; then
  echo "Simulation did not produce expected package: $ZIP_PATH" >&2
  exit 1
fi

package_bytes="$(wc -c < "$ZIP_PATH" | tr -d ' ')"
package_files="$(unzip -Z1 "$ZIP_PATH" | wc -l | tr -d ' ')"
changelog_entries="$(grep -c '^\* ' "$NOTES_FILE" || true)"

wp_org_deploy_state="disabled"
if [ "${WP_ORG_DEPLOY_ENABLED:-false}" = "true" ]; then
  wp_org_deploy_state="enabled"
fi

echo "=== Release Simulation ==="
echo "Version: $VERSION"
echo "Changelog entries: $changelog_entries"
echo "Package: $ZIP_FILE (${package_bytes} bytes, ${package_files} files)"
echo "WP.org deploy: $wp_org_deploy_state"
echo
echo "Changelog preview:"
cat "$NOTES_FILE"
echo
echo "Files changed by version bump simulation:"
if [ -s "$DIFF_FILE" ]; then
  cat "$DIFF_FILE"
else
  echo "(none)"
fi
