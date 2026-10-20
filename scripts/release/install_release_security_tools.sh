#!/usr/bin/env bash

set -euo pipefail

DEST_DIR="${1:-}"
SYFT_VERSION='1.55.0'
COSIGN_VERSION='3.1.4'

if [ -z "$DEST_DIR" ]; then
  echo "Usage: $0 <destination-dir>" >&2
  exit 1
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

case "${OS}:${ARCH}" in
  Linux:x86_64)
    syft_archive="syft_${SYFT_VERSION}_linux_amd64.tar.gz"
    syft_sha256='bb65249542db5fedeeb4d3f9b018b75e7264dbfbbb10486f044581a92f90490d'
    cosign_asset='cosign-linux-amd64'
    cosign_sha256='424e2c97d0b45fd7a6b608a87f090f35633f4c23ece5f092d48bba11aaf4bbfa'
    ;;
  Darwin:x86_64)
    syft_archive="syft_${SYFT_VERSION}_darwin_amd64.tar.gz"
    syft_sha256='e2e5831cbabaec9a36fe65c34755c1113982c842a685edce3ce0b54a0ded8003'
    cosign_asset='cosign-darwin-amd64'
    cosign_sha256='9d1e4abe2b6be279ed0d2ff706fde1ccd738747c834e3e6d44039c238867334f'
    ;;
  Darwin:arm64)
    syft_archive="syft_${SYFT_VERSION}_darwin_arm64.tar.gz"
    syft_sha256='1217c258bd5eb91ef3189cf22a82e02f9cac07e4ce934350f428e93aff674625'
    cosign_asset='cosign-darwin-arm64'
    cosign_sha256='9f9b8cd557cf2e5b3df3373a00baa005a86b02391e3e06dd0ce37b3a1533d3a4'
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
