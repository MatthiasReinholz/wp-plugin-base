#!/usr/bin/env bash

set -euo pipefail

ARTIFACT_PATH="${1:-}"
BUNDLE_PATH="${2:-}"

if [ -z "$ARTIFACT_PATH" ] || [ -z "$BUNDLE_PATH" ]; then
  echo "Usage: $0 <artifact-path> <bundle-path>" >&2
  exit 1
fi

if ! command -v cosign >/dev/null 2>&1; then
  echo "cosign is required to sign release artifacts." >&2
  exit 1
fi

if [ ! -f "$ARTIFACT_PATH" ]; then
  echo "Release artifact not found: $ARTIFACT_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$BUNDLE_PATH")"

cosign sign-blob --yes --bundle "$BUNDLE_PATH" "$ARTIFACT_PATH" >/dev/null

echo "Signed $ARTIFACT_PATH with keyless Sigstore bundle $BUNDLE_PATH"
