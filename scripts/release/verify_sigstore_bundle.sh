#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"

wp_plugin_base_require_commands "Sigstore bundle verification" cosign

REPOSITORY="${1:-}"
ARTIFACT_PATH="${2:-}"
BUNDLE_PATH="${3:-}"
VERIFICATION_SCOPE="${4:-plugin}"
SOURCE_PROVIDER="${5:-${FOUNDATION_RELEASE_SOURCE_PROVIDER:-github-release}}"
SOURCE_API_BASE="${6:-${FOUNDATION_RELEASE_SOURCE_API_BASE:-}}"
SOURCE_ISSUER="${7:-${FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER:-}}"

if [ -z "$REPOSITORY" ] || [ -z "$ARTIFACT_PATH" ] || [ -z "$BUNDLE_PATH" ]; then
  echo "Usage: $0 <reference> <artifact-path> <bundle-path> [plugin|foundation] [provider] [api-base] [issuer]" >&2
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

if [ -z "$SOURCE_API_BASE" ]; then
  SOURCE_API_BASE="$(wp_plugin_base_provider_default_api_base "$SOURCE_PROVIDER")"
fi

identity_regex="${WP_PLUGIN_BASE_SIGSTORE_CERTIFICATE_IDENTITY_REGEXP:-}"
issuer="${WP_PLUGIN_BASE_SIGSTORE_CERTIFICATE_OIDC_ISSUER:-}"

if [ -z "$identity_regex" ]; then
  identity_regex="$(wp_plugin_base_provider_sigstore_identity_regex "$SOURCE_PROVIDER" "$SOURCE_API_BASE" "$REPOSITORY" "$VERIFICATION_SCOPE")"
fi

if [ -z "$issuer" ]; then
  issuer="$SOURCE_ISSUER"
fi

if [ -z "$issuer" ]; then
  issuer="$(wp_plugin_base_provider_sigstore_oidc_issuer "$SOURCE_PROVIDER" "$SOURCE_API_BASE")"
fi

if [ -z "$identity_regex" ] || [ -z "$issuer" ]; then
  echo "Unable to resolve Sigstore verification identity for provider ${SOURCE_PROVIDER}." >&2
  exit 1
fi

cosign verify-blob \
  --bundle "$BUNDLE_PATH" \
  --certificate-identity-regexp "$identity_regex" \
  --certificate-oidc-issuer "$issuer" \
  "$ARTIFACT_PATH" >/dev/null

echo "Verified Sigstore bundle for $ARTIFACT_PATH (scope=$VERIFICATION_SCOPE, provider=$SOURCE_PROVIDER)."
