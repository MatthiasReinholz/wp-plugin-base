#!/usr/bin/env bash

set -euo pipefail

DEST_DIR="${1:-}"
SYFT_VERSION='1.52.0'
COSIGN_VERSION='3.1.3'

if [ -z "$DEST_DIR" ]; then
  echo "Usage: $0 <destination-dir>" >&2
  exit 1
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

case "${OS}:${ARCH}" in
  Linux:x86_64)
    syft_archive="syft_${SYFT_VERSION}_linux_amd64.tar.gz"
    syft_sha256='caeedb81fb0491615f1ebd1761e4145d41ee86dd2cc7bf80669f9f5ad9d6133d'
    cosign_asset='cosign-linux-amd64'
    cosign_sha256='4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71'
    ;;
  Darwin:x86_64)
    syft_archive="syft_${SYFT_VERSION}_darwin_amd64.tar.gz"
    syft_sha256='56975f5d7ffa9846a1eaf64330647841b878097bc7e3730cb9325f93add96917'
    cosign_asset='cosign-darwin-amd64'
    cosign_sha256='2347488e5d5b25336644024dfeca5601b190e91197a71a917bda44744aff106c'
    ;;
  Darwin:arm64)
    syft_archive="syft_${SYFT_VERSION}_darwin_arm64.tar.gz"
    syft_sha256='014d561b6d13059124155f74a6c5a9a99501f5e209313638dd884f39eb418ee6'
    cosign_asset='cosign-darwin-arm64'
    cosign_sha256='5cf948c2f4dfe59687bdd0b8523709067383e03982cc543475c8a7dc70e92a76'
    ;;
  *)
    echo "Release security tool installation is unsupported on ${OS}/${ARCH}." >&2
    exit 1
    ;;
esac

mkdir -p "$DEST_DIR"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

sha256_check() {
  local expected="$1"
  local file="$2"

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s  %s\n' "$expected" "$file" | sha256sum -c -
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    printf '%s  %s\n' "$expected" "$file" | shasum -a 256 -c -
    return 0
  fi

  echo "No SHA-256 verification tool available." >&2
  exit 1
}

download_release_tool() {
  local url="$1"
  local output="$2"

  curl -fsSLo "$output" \
    --retry 3 \
    --retry-delay 2 \
    --retry-connrefused \
    "$url"
}

download_release_tool \
  "https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/${syft_archive}" \
  "$TMP_DIR/$syft_archive"
sha256_check "$syft_sha256" "$TMP_DIR/$syft_archive"
tar -xzf "$TMP_DIR/$syft_archive" -C "$TMP_DIR"
install "$TMP_DIR/syft" "$DEST_DIR/syft"

download_release_tool \
  "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/${cosign_asset}" \
  "$TMP_DIR/$cosign_asset"
sha256_check "$cosign_sha256" "$TMP_DIR/$cosign_asset"
install "$TMP_DIR/$cosign_asset" "$DEST_DIR/cosign"

echo "Installed syft and cosign into $DEST_DIR"
