#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

VERSION="${1:-}"
CONFIG_OVERRIDE="${2:-}"
SOURCE_OVERRIDE="${3:-}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z [config-path] [source-dir]" >&2
  exit 1
fi

wp_plugin_base_load_config "$CONFIG_OVERRIDE"
wp_plugin_base_require_vars PLUGIN_SLUG WORDPRESS_ORG_SLUG SVN_USERNAME SVN_PASSWORD

SOURCE_DIR="${SOURCE_OVERRIDE:-$ROOT_DIR/dist/package/$PLUGIN_SLUG}"
ASSETS_DIR="$ROOT_DIR/.wordpress-org"
SVN_URL="https://plugins.svn.wordpress.org/$WORDPRESS_ORG_SLUG"
WORK_DIR="$(mktemp -d)"
SVN_DIR="$WORK_DIR/svn"
SVN_ARGS=(--non-interactive --no-auth-cache --username "$SVN_USERNAME" --password "$SVN_PASSWORD")

cleanup() {
  rm -rf "$WORK_DIR"
}

trap cleanup EXIT

if [ ! -d "$SOURCE_DIR" ]; then
  echo "WordPress.org deploy source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

svn checkout "${SVN_ARGS[@]}" --depth immediates "$SVN_URL" "$SVN_DIR" >/dev/null

mkdir -p "$SVN_DIR/trunk" "$SVN_DIR/tags" "$SVN_DIR/assets"
svn update "${SVN_ARGS[@]}" --set-depth infinity "$SVN_DIR/trunk" "$SVN_DIR/tags" "$SVN_DIR/assets" >/dev/null

mkdir -p "$SVN_DIR/tags/$VERSION"

rsync -a --delete --exclude '.svn' "$SOURCE_DIR/" "$SVN_DIR/trunk/"
rsync -a --delete --exclude '.svn' "$SOURCE_DIR/" "$SVN_DIR/tags/$VERSION/"

if [ -d "$ASSETS_DIR" ]; then
  rsync -a --delete --exclude '.svn' "$ASSETS_DIR/" "$SVN_DIR/assets/"
fi

while IFS= read -r status_line; do
  [ -n "$status_line" ] || continue
  status="${status_line:0:1}"
  path="${status_line:8}"

  case "$status" in
    \?)
      svn add --parents "${SVN_ARGS[@]}" "$path" >/dev/null
      ;;
    !)
      svn delete --force "${SVN_ARGS[@]}" "$path" >/dev/null
      ;;
  esac
done < <(cd "$SVN_DIR" && svn status)

if [ -z "$(cd "$SVN_DIR" && svn status)" ]; then
  echo "No WordPress.org changes to commit for ${VERSION}."
  exit 0
fi

(cd "$SVN_DIR" && svn commit "${SVN_ARGS[@]}" -m "Release $VERSION") >/dev/null
echo "Deployed $WORDPRESS_ORG_SLUG $VERSION to WordPress.org"
