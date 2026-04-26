#!/usr/bin/env bash

set -euo pipefail

DEST_DIR="${1:-}"
SYFT_VERSION='1.43.0'
COSIGN_VERSION='3.0.6'

if [ -z "$DEST_DIR" ]; then
  echo "Usage: $0 <destination-dir>" >&2
  exit 1
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

case "${OS}:${ARCH}" in
  Linux:x86_64)
    syft_archive="syft_${SYFT_VERSION}_linux_amd64.tar.gz"
    syft_sha256='7b98251d2d08926bb5d4639b56b1f0996a58ef6667c5830e3fe3cd3ad5f4214a'
    cosign_asset='cosign-linux-amd64'
    cosign_sha256='c956e5dfcac53d52bcf058360d579472f0c1d2d9b69f55209e256fe7783f4c74'
    ;;
  *)
    echo "Release security tool installation is supported only on Linux/x86_64 runners." >&2
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
  printf '%s  %s\n' "$expected" "$file" | sha256sum -c -
}

curl -fsSLo "$TMP_DIR/$syft_archive" \
  "https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/${syft_archive}"
sha256_check "$syft_sha256" "$TMP_DIR/$syft_archive"
tar -xzf "$TMP_DIR/$syft_archive" -C "$TMP_DIR"
install "$TMP_DIR/syft" "$DEST_DIR/syft"

curl -fsSLo "$TMP_DIR/$cosign_asset" \
  "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/${cosign_asset}"
sha256_check "$cosign_sha256" "$TMP_DIR/$cosign_asset"
install "$TMP_DIR/$cosign_asset" "$DEST_DIR/cosign"

echo "Installed syft and cosign into $DEST_DIR"
