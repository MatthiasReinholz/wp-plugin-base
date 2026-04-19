#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

VERSION="${1:-${CI_COMMIT_TAG:-}}"
CONFIG_OVERRIDE="${2:-${WP_PLUGIN_BASE_CONFIG:-.wp-plugin-base.env}}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 <x.y.z> [config-path]" >&2
  exit 1
fi

if ! git rev-parse --verify --quiet "refs/tags/${VERSION}" >/dev/null; then
  echo "Tag ${VERSION} not found. run_gitlab_release.sh requires an existing tag." >&2
  exit 1
fi

wp_plugin_base_require_commands "GitLab release orchestration" git php node jq zip unzip rsync curl perl ruby

wp_plugin_base_load_config "$CONFIG_OVERRIDE"
wp_plugin_base_require_vars PLUGIN_SLUG ZIP_FILE

repository="${CI_PROJECT_PATH:-${AUTOMATION_PROJECT_PATH:-}}"
if [ -z "$repository" ]; then
  echo "CI_PROJECT_PATH or AUTOMATION_PROJECT_PATH is required." >&2
  exit 1
fi

commit_sha="$(git rev-parse HEAD)"
bash "$SCRIPT_DIR/../ci/check_release_pr.sh" "$repository" "$VERSION" "$commit_sha"

if wp_plugin_base_is_true "${WORDPRESS_READINESS_ENABLED:-false}"; then
  WP_PLUGIN_BASE_STRICT_DEPLOY_ENV_PROTECTION="${WP_PLUGIN_BASE_STRICT_DEPLOY_ENV_PROTECTION:-false}" \
    bash "$SCRIPT_DIR/../ci/validate_wordpress_readiness.sh" "$CONFIG_OVERRIDE"
else
  bash "$SCRIPT_DIR/../ci/check_versions.sh" "$VERSION" "$CONFIG_OVERRIDE"
  bash "$SCRIPT_DIR/../ci/lint_php.sh" "$CONFIG_OVERRIDE"
  bash "$SCRIPT_DIR/../ci/lint_js.sh" "$CONFIG_OVERRIDE"
  bash "$SCRIPT_DIR/../ci/build_zip.sh" "$CONFIG_OVERRIDE"
fi

bash "$SCRIPT_DIR/generate_github_release_body.sh" "$VERSION" "$CONFIG_OVERRIDE" > "$ROOT_DIR/dist/release-body.md"
bash "$SCRIPT_DIR/install_release_security_tools.sh" "$ROOT_DIR/dist/.release-tools"
export PATH="$ROOT_DIR/dist/.release-tools:$PATH"

bash "$SCRIPT_DIR/generate_sbom.sh" \
  "$ROOT_DIR/dist/package/${PLUGIN_SLUG}" \
  "$ROOT_DIR/dist/${ZIP_FILE}.sbom.cdx.json"
bash "$SCRIPT_DIR/sign_release.sh" \
  "$ROOT_DIR/dist/${ZIP_FILE}" \
  "$ROOT_DIR/dist/${ZIP_FILE}.sigstore.json"

if [ "${WP_ORG_DEPLOY_ENABLED:-false}" = "true" ] && [ "${WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY:-false}" = "true" ]; then
  bash "$SCRIPT_DIR/validate_wordpress_org_deploy.sh" "$VERSION" "$CONFIG_OVERRIDE" "$ROOT_DIR/dist/package/${PLUGIN_SLUG}"
  wp_plugin_base_require_commands "WordPress.org deploy" svn
  bash "$SCRIPT_DIR/deploy_wordpress_org.sh" "$VERSION" "$CONFIG_OVERRIDE" "$ROOT_DIR/dist/package/${PLUGIN_SLUG}"
elif [ "${WP_ORG_DEPLOY_ENABLED:-false}" = "true" ]; then
  echo "GitLab repair release skips WordPress.org redeploy unless WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY=true is set."
fi

if [ "${WOOCOMMERCE_COM_DEPLOY_ENABLED:-false}" = "true" ]; then
  bash "$SCRIPT_DIR/validate_woocommerce_com_deploy.sh" "$VERSION" "$CONFIG_OVERRIDE" "$ROOT_DIR/dist/package/${PLUGIN_SLUG}"
fi

bash "$SCRIPT_DIR/publish_gitlab_release.sh" --repair \
  "$VERSION" \
  "$VERSION" \
  "$ROOT_DIR/dist/release-body.md" \
  "$ROOT_DIR/dist/${ZIP_FILE}" \
  "$ROOT_DIR/dist/${ZIP_FILE}.sbom.cdx.json" \
  "$ROOT_DIR/dist/${ZIP_FILE}.sigstore.json"

if [ "${WOOCOMMERCE_COM_DEPLOY_ENABLED:-false}" = "true" ] && [ -n "${WOOCOMMERCE_COM_PRODUCT_ID:-}" ]; then
  WP_PLUGIN_BASE_REPAIR_MODE=true \
    bash "$SCRIPT_DIR/deploy_woocommerce_com.sh" "$VERSION" "$CONFIG_OVERRIDE" "$ROOT_DIR/dist/${ZIP_FILE}"
fi
