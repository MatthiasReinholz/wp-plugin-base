#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

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

sign_release_artifact() {
  rm -f "$BUNDLE_PATH"
  cosign sign-blob --yes --bundle "$BUNDLE_PATH" "$ARTIFACT_PATH" >/dev/null
}

wp_plugin_base_run_with_retry 3 5 "Sigstore release artifact signing" sign_release_artifact

echo "Signed $ARTIFACT_PATH with keyless Sigstore bundle $BUNDLE_PATH"
