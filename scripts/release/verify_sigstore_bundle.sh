#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "Sigstore bundle verification" cosign

REPOSITORY="${1:-}"
ARTIFACT_PATH="${2:-}"
BUNDLE_PATH="${3:-}"
VERIFICATION_SCOPE="${4:-plugin}"

if [ -z "$REPOSITORY" ] || [ -z "$ARTIFACT_PATH" ] || [ -z "$BUNDLE_PATH" ]; then
  echo "Usage: $0 <owner/repo> <artifact-path> <bundle-path> [plugin|foundation]" >&2
  exit 1
fi

if [ ! -f "$ARTIFACT_PATH" ]; then
  echo "Artifact not found: $ARTIFACT_PATH" >&2
  exit 1
fi

if [ ! -f "$BUNDLE_PATH" ]; then
  echo "Sigstore bundle not found: $BUNDLE_PATH" >&2
  exit 1
fi

case "$VERIFICATION_SCOPE" in
  plugin)
    identity_regex="^https://github.com/${REPOSITORY}/.github/workflows/(finalize-release|release)\\.yml@refs/heads/main$"
    ;;
  foundation)
    identity_regex="^https://github.com/${REPOSITORY}/.github/workflows/(finalize-foundation-release|release-foundation)\\.yml@refs/heads/main$"
    ;;
  *)
    echo "Unsupported verification scope: $VERIFICATION_SCOPE" >&2
    exit 1
    ;;
esac

cosign verify-blob \
  --bundle "$BUNDLE_PATH" \
  --certificate-identity-regexp "$identity_regex" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "$ARTIFACT_PATH" >/dev/null

echo "Verified Sigstore bundle for $ARTIFACT_PATH (scope=$VERIFICATION_SCOPE)."
