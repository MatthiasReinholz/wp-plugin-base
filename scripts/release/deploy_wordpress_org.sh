#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "WordPress.org deployment" git python3 rsync svn

VERSION="${1:-}"
CONFIG_OVERRIDE="${2:-}"
SOURCE_OVERRIDE="${3:-}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z [config-path] [source-dir]" >&2
  exit 1
fi

wp_plugin_base_load_config "$CONFIG_OVERRIDE"
wp_plugin_base_require_vars PLUGIN_SLUG WORDPRESS_ORG_SLUG ZIP_FILE
wp_plugin_base_require_vars SVN_USERNAME SVN_PASSWORD

SOURCE_DIR="${SOURCE_OVERRIDE:-$ROOT_DIR/dist/package/$PLUGIN_SLUG}"
LOCAL_ZIP_PATH="$ROOT_DIR/dist/$ZIP_FILE"
ASSETS_DIR="$ROOT_DIR/.wordpress-org"
ALLOW_TAG_REDEPLOY="${WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY:-false}"
SVN_HOST="plugins.svn.wordpress.org"
SVN_SCHEME="https"
SVN_PORT="443"
SVN_URL="${SVN_SCHEME}://${SVN_HOST}/$WORDPRESS_ORG_SLUG"
WORK_DIR="$(mktemp -d)"
SVN_DIR="$WORK_DIR/svn"
SVN_CONFIG_DIR="$WORK_DIR/subversion-config"
SVN_REALM_DEFAULT="<${SVN_SCHEME}://${SVN_HOST}:${SVN_PORT}> Use your WordPress.org login"
SVN_REALM="${SVN_REALM:-$SVN_REALM_DEFAULT}"
SVN_ARGS=(--non-interactive --config-dir "$SVN_CONFIG_DIR" --username "$SVN_USERNAME")

cleanup() {
  rm -rf "$WORK_DIR"
}

trap cleanup EXIT

if [ ! -d "$SOURCE_DIR" ]; then
  echo "WordPress.org deploy source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

bash "$SCRIPT_DIR/validate_wordpress_org_deploy.sh" "$VERSION" "$CONFIG_OVERRIDE" "$SOURCE_DIR"

mkdir -p "$SVN_CONFIG_DIR"
python3 "$SCRIPT_DIR/../lib/write_svn_simple_auth.py" \
  "$SVN_CONFIG_DIR" \
  "$SVN_REALM" \
  "$SVN_USERNAME"

svn checkout "${SVN_ARGS[@]}" --depth immediates "$SVN_URL" "$SVN_DIR" >/dev/null

mkdir -p "$SVN_DIR/trunk" "$SVN_DIR/tags" "$SVN_DIR/assets"
svn update "${SVN_ARGS[@]}" --set-depth infinity "$SVN_DIR/trunk" "$SVN_DIR/tags" "$SVN_DIR/assets" >/dev/null

tag_dir="$SVN_DIR/tags/$VERSION"
tag_exists=false
tag_diff=''
latest_repo_version=''

latest_repo_version="$(git -C "$ROOT_DIR" tag --list '[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1 || true)"

if svn info "${SVN_ARGS[@]}" "$tag_dir" >/dev/null 2>&1; then
  tag_exists=true
  tag_diff="$(rsync -ani --delete --exclude '.svn' "$SOURCE_DIR/" "$tag_dir/" || true)"
  if [ "$ALLOW_TAG_REDEPLOY" = "true" ] && [ -n "$latest_repo_version" ] && [ "$VERSION" != "$latest_repo_version" ]; then
    echo "WordPress.org repair deploy is only allowed for the latest repository release tag (${latest_repo_version}). Refusing to redeploy older version ${VERSION} to trunk." >&2
    exit 1
  fi
  if [ -n "$tag_diff" ] && [ "$ALLOW_TAG_REDEPLOY" != "true" ]; then
    echo "WordPress.org tag ${VERSION} already exists and differs from the release package. Refusing to mutate an existing release tag." >&2
    exit 1
  fi
else
  mkdir -p "$tag_dir"
fi

rsync -a --delete --exclude '.svn' "$SOURCE_DIR/" "$SVN_DIR/trunk/"
if [ "$tag_exists" != "true" ] || [ "$ALLOW_TAG_REDEPLOY" = "true" ]; then
  rsync -a --delete --exclude '.svn' "$SOURCE_DIR/" "$tag_dir/"
fi

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

TAG_URL="https://plugins.svn.wordpress.org/${WORDPRESS_ORG_SLUG}/tags/${VERSION}/"
echo "Verifying WordPress.org tag availability: $TAG_URL"
tag_verified=false
for attempt in 1 2 3 4 5; do
  if svn ls "${SVN_ARGS[@]}" "$TAG_URL" >/dev/null 2>&1; then
    tag_verified=true
    break
  fi
  sleep $((attempt * 5))
done

if [ "$tag_verified" != "true" ]; then
  echo "WordPress.org tag verification failed for ${VERSION}: ${TAG_URL}" >&2
  exit 1
fi

echo "Verified WordPress.org tag ${VERSION}."

if command -v curl >/dev/null 2>&1 && [ -f "$LOCAL_ZIP_PATH" ]; then
  download_url="https://downloads.wordpress.org/plugin/${WORDPRESS_ORG_SLUG}.${VERSION}.zip"
  remote_zip="$(mktemp)"
  if curl -fsSL --connect-timeout 10 --max-time 60 "$download_url" -o "$remote_zip"; then
    local_sha=""
    remote_sha=""
    if command -v sha256sum >/dev/null 2>&1; then
      local_sha="$(sha256sum "$LOCAL_ZIP_PATH" | awk '{print $1}')"
      remote_sha="$(sha256sum "$remote_zip" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
      local_sha="$(shasum -a 256 "$LOCAL_ZIP_PATH" | awk '{print $1}')"
      remote_sha="$(shasum -a 256 "$remote_zip" | awk '{print $1}')"
    fi

    if [ -n "$local_sha" ] && [ -n "$remote_sha" ] && [ "$local_sha" != "$remote_sha" ]; then
      echo "WARNING: Downloaded WordPress.org ZIP checksum differs from local artifact. This can happen when packaging metadata differs upstream." >&2
    fi
  else
    echo "WARNING: Could not download WordPress.org ZIP for checksum comparison yet: $download_url" >&2
  fi
  rm -f "$remote_zip"
fi
