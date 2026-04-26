#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

VERSION="${1:-}"
EXPECTED_PRERELEASE="${2:-}"

if [ -z "$VERSION" ] || [ -z "$EXPECTED_PRERELEASE" ] || [ "$#" -lt 3 ]; then
  echo "Usage: $0 <version> <expected-prerelease:true|false> <asset> [asset...]" >&2
  exit 1
fi

shift 2

case "$EXPECTED_PRERELEASE" in
  true|false)
    ;;
  *)
    echo "Expected prerelease value must be true or false." >&2
    exit 1
    ;;
esac

wp_plugin_base_require_commands "GitHub release asset verification" gh jq

if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "GitHub release asset verification requires sha256sum or shasum." >&2
  exit 1
fi

REPOSITORY="${GITHUB_REPOSITORY:-}"
if [ -z "$REPOSITORY" ]; then
  echo "GITHUB_REPOSITORY is required for GitHub release verification." >&2
  exit 1
fi

download_dir="$(mktemp -d)"
release_json="$(mktemp)"

cleanup() {
  rm -rf "$download_dir" "$release_json"
}
trap cleanup EXIT

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi

  shasum -a 256 "$1" | awk '{print $1}'
}

gh release view "$VERSION" --repo "$REPOSITORY" --json isDraft,isPrerelease,assets > "$release_json"

if [ "$(jq -r '.isDraft' "$release_json")" = "true" ]; then
  echo "Release $VERSION is still a draft." >&2
  exit 1
fi

if [ "$(jq -r '.isPrerelease' "$release_json")" != "$EXPECTED_PRERELEASE" ]; then
  echo "Release $VERSION has unexpected prerelease state." >&2
  exit 1
fi

for asset_path in "$@"; do
  if [ ! -s "$asset_path" ]; then
    echo "Local release asset is missing or empty: $asset_path" >&2
    exit 1
  fi

  asset_name="$(basename "$asset_path")"
  asset_count="$(
    jq --arg name "$asset_name" '[.assets[] | select(.name == $name and .size > 0)] | length' "$release_json"
  )"
  if [ "$asset_count" != "1" ]; then
    echo "Release $VERSION is missing a non-empty asset named $asset_name." >&2
    exit 1
  fi

  rm -f "$download_dir/$asset_name"
  gh release download "$VERSION" \
    --repo "$REPOSITORY" \
    --dir "$download_dir" \
    --pattern "$asset_name" \
    --clobber >/dev/null

  if [ ! -s "$download_dir/$asset_name" ]; then
    echo "Downloaded release asset is missing or empty: $asset_name" >&2
    exit 1
  fi

  local_hash="$(hash_file "$asset_path")"
  remote_hash="$(hash_file "$download_dir/$asset_name")"
  if [ "$local_hash" != "$remote_hash" ]; then
    echo "Published release asset hash mismatch for $asset_name." >&2
    exit 1
  fi
done

echo "Verified GitHub release assets for $VERSION."
