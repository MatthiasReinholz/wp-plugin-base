#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

MODE="ci"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      if [ "$#" -lt 2 ]; then
        echo "--mode requires a value." >&2
        exit 1
      fi
      MODE="$2"
      shift 2
      ;;
    --mode=*)
      MODE="${1#*=}"
      shift
      ;;
    *)
      echo "Unsupported argument: $1" >&2
      exit 1
      ;;
  esac
done

case "$MODE" in
  ci|local-required|local-lite)
    ;;
  *)
    echo "Unsupported mode: $MODE" >&2
    exit 1
    ;;
esac

wp_plugin_base_require_commands "release security smoke" git php node ruby perl rsync zip unzip jq

fixture=""
tools_dir=""

cleanup() {
  rm -rf "$fixture" "$tools_dir"
}

trap cleanup EXIT

have_release_tools=true
if ! command -v syft >/dev/null 2>&1 || ! command -v cosign >/dev/null 2>&1; then
  have_release_tools=false
fi

if [ "$have_release_tools" != true ] && [ "$MODE" = "ci" ]; then
  if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
    echo "CI release security smoke requires Linux/x86_64 when release tools are not preinstalled." >&2
    exit 1
  fi

  tools_dir="$(mktemp -d)"
  bash "$ROOT_DIR/scripts/release/install_release_security_tools.sh" "$tools_dir" >/dev/null
  export PATH="$tools_dir:$PATH"
  have_release_tools=true
fi

if [ "$have_release_tools" != true ] && [ "$MODE" = "local-required" ]; then
  echo "Release security smoke requires syft and cosign in local-required mode." >&2
  echo "Run scripts/foundation/bootstrap_strict_local.sh and prepend its tools directory to PATH." >&2
  exit 1
fi

fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$fixture/"
mkdir -p "$fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" "release/1.2.3"
WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh"

cat > "$fixture/dist/foundation-release.json" <<EOF
{
  "repository": "${GITHUB_REPOSITORY:-local/wp-plugin-base}",
  "version": "v1.2.3",
  "commit": "$(git -C "$ROOT_DIR" rev-parse HEAD)"
}
EOF

if [ "$have_release_tools" != true ]; then
  echo "Release security tools are unavailable locally; skipping SBOM and Sigstore checks."
  exit 0
fi

bash "$ROOT_DIR/scripts/release/generate_sbom.sh" \
  "$fixture/dist/package/standard-plugin" \
  "$fixture/dist/standard-plugin.zip.sbom.cdx.json"
jq -e '.bomFormat == "CycloneDX"' "$fixture/dist/standard-plugin.zip.sbom.cdx.json" >/dev/null
jq -e '.specVersion | strings' "$fixture/dist/standard-plugin.zip.sbom.cdx.json" >/dev/null

bash "$ROOT_DIR/scripts/release/generate_sbom.sh" \
  "$ROOT_DIR" \
  "$fixture/dist/foundation-release.sbom.cdx.json"
jq -e '.bomFormat == "CycloneDX"' "$fixture/dist/foundation-release.sbom.cdx.json" >/dev/null
jq -e '.specVersion | strings' "$fixture/dist/foundation-release.sbom.cdx.json" >/dev/null

if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] || [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
  if [ "$MODE" = "ci" ]; then
    echo "CI release security smoke requires GitHub Actions OIDC token access." >&2
    exit 1
  fi

  echo "Local SBOM checks completed. Sigstore signing checks require GitHub Actions OIDC and are enforced in ci mode."
  exit 0
fi

bash "$ROOT_DIR/scripts/release/sign_release.sh" \
  "$fixture/dist/standard-plugin.zip" \
  "$fixture/dist/standard-plugin.zip.sigstore.json"
cosign verify-blob \
  --bundle "$fixture/dist/standard-plugin.zip.sigstore.json" \
  --certificate-identity-regexp "^https://github.com/${GITHUB_REPOSITORY}/.github/workflows/.+@refs/(heads/.+|pull/.+/merge)$" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "$fixture/dist/standard-plugin.zip" >/dev/null

bash "$ROOT_DIR/scripts/release/sign_release.sh" \
  "$fixture/dist/foundation-release.json" \
  "$fixture/dist/foundation-release.json.sigstore.json"
cosign verify-blob \
  --bundle "$fixture/dist/foundation-release.json.sigstore.json" \
  --certificate-identity-regexp "^https://github.com/${GITHUB_REPOSITORY}/.github/workflows/.+@refs/(heads/.+|pull/.+/merge)$" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "$fixture/dist/foundation-release.json" >/dev/null

echo "Validated release security smoke path."
