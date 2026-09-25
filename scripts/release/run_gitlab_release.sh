#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"
# shellcheck source=../lib/package_generation.sh
. "$SCRIPT_DIR/../lib/package_generation.sh"

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
wp_plugin_base_require_managed_automation "release and deployment"
wp_plugin_base_require_vars PLUGIN_SLUG ZIP_FILE

repository="${CI_PROJECT_PATH:-${AUTOMATION_PROJECT_PATH:-}}"
if [ -z "$repository" ]; then
  echo "CI_PROJECT_PATH or AUTOMATION_PROJECT_PATH is required." >&2
  exit 1
fi

if [ "$(git cat-file -t "refs/tags/$VERSION")" != "tag" ]; then
  echo "Release tag $VERSION must be annotated." >&2
  exit 1
fi
commit_sha="$(git rev-parse HEAD)"
if [ "$(git rev-list -n 1 "refs/tags/$VERSION")" != "$commit_sha" ]; then
  echo "Release checkout does not match tag $VERSION." >&2
  exit 1
fi
if [ -z "${SIGSTORE_ID_TOKEN:-}" ]; then
  echo "GitLab release signing requires SIGSTORE_ID_TOKEN with audience sigstore." >&2
  exit 1
fi
git fetch origin "${DEFAULT_BRANCH:-main}" --tags
git merge-base --is-ancestor "$commit_sha" "origin/${DEFAULT_BRANCH:-main}"
bash "$SCRIPT_DIR/../ci/check_release_pr.sh" "$repository" "$VERSION" "$commit_sha"

bash "$SCRIPT_DIR/install_release_security_tools.sh" "$ROOT_DIR/dist/.release-tools"
export PATH="$ROOT_DIR/dist/.release-tools:$PATH"

PACKAGE_RESULT="$(mktemp)"
trap 'rm -f "$PACKAGE_RESULT"' EXIT
export WP_PLUGIN_BASE_PACKAGE_RESULT_FILE="$PACKAGE_RESULT"
restore_status=3
if ! wp_plugin_base_is_true "${WP_PLUGIN_BASE_REPAIR_HOST_ASSETS:-false}"; then
  if bash "$SCRIPT_DIR/restore_gitlab_release_assets.sh" "$VERSION" "$CONFIG_OVERRIDE"; then
    restore_status=0
  else
    restore_status=$?
    if [ "$restore_status" -ne 3 ]; then
      echo "Existing release recovery failed; inspect its assets before requesting explicit host repair." >&2
      exit "$restore_status"
    fi
  fi
fi

if [ "$restore_status" -eq 3 ]; then
  if wp_plugin_base_is_true "${WORDPRESS_READINESS_ENABLED:-false}"; then
    WP_PLUGIN_BASE_STRICT_DEPLOY_ENV_PROTECTION="${WP_PLUGIN_BASE_STRICT_DEPLOY_ENV_PROTECTION:-false}" \
      WP_PLUGIN_BASE_PROJECT_PACKAGE_RESULT_FILE="$PACKAGE_RESULT" bash "$SCRIPT_DIR/../ci/validate_wordpress_readiness.sh" "$CONFIG_OVERRIDE"
  else
    bash "$SCRIPT_DIR/../ci/check_versions.sh" "$VERSION" "$CONFIG_OVERRIDE"
    bash "$SCRIPT_DIR/../ci/lint_php.sh" "$CONFIG_OVERRIDE"
    bash "$SCRIPT_DIR/../ci/lint_js.sh" "$CONFIG_OVERRIDE"
    bash "$SCRIPT_DIR/../ci/build_zip.sh" "$CONFIG_OVERRIDE"
  fi

  wp_plugin_base_capture_package "$PACKAGE_RESULT"
  bash "$SCRIPT_DIR/generate_github_release_body.sh" "$VERSION" "$CONFIG_OVERRIDE" > "$ROOT_DIR/dist/release-body.md"
  bash "$SCRIPT_DIR/generate_sbom.sh" \
    "$WP_PLUGIN_BASE_PACKAGE_DIR" \
    "$WP_PLUGIN_BASE_PACKAGE_SBOM"
  bash "$SCRIPT_DIR/sign_release.sh" \
    "$WP_PLUGIN_BASE_PACKAGE_ZIP" \
    "$WP_PLUGIN_BASE_PACKAGE_SIGNATURE"

  bash "$SCRIPT_DIR/verify_sigstore_bundle.sh" "$repository" \
    "$WP_PLUGIN_BASE_PACKAGE_ZIP" "$WP_PLUGIN_BASE_PACKAGE_SIGNATURE" \
    plugin gitlab-release "$AUTOMATION_API_BASE" "" "$VERSION"
fi

wp_plugin_base_capture_package "$PACKAGE_RESULT"

if [ "${WP_ORG_DEPLOY_ENABLED:-false}" = "true" ]; then
  bash "$SCRIPT_DIR/validate_wordpress_org_deploy.sh" "$VERSION" "$CONFIG_OVERRIDE" "$WP_PLUGIN_BASE_PACKAGE_DIR"
fi

if [ "${WOOCOMMERCE_COM_DEPLOY_ENABLED:-false}" = "true" ]; then
  bash "$SCRIPT_DIR/validate_woocommerce_com_deploy.sh" "$VERSION" "$CONFIG_OVERRIDE" "$WP_PLUGIN_BASE_PACKAGE_DIR"
fi

if [ "$restore_status" -eq 3 ]; then
  python3 "$WP_PLUGIN_BASE_PACKAGE_HELPER" check "$WP_PLUGIN_BASE_PACKAGE_DESCRIPTOR"
  bash "$SCRIPT_DIR/publish_gitlab_release.sh" --repair \
    "$VERSION" \
    "$VERSION" \
    "$ROOT_DIR/dist/release-body.md" \
    "$WP_PLUGIN_BASE_PACKAGE_ZIP" \
    "$WP_PLUGIN_BASE_PACKAGE_SBOM" \
    "$WP_PLUGIN_BASE_PACKAGE_SIGNATURE"
fi

# Channel state is checked independently of host repair. Existing matching SVN
# tags are idempotent; changing their contents still needs the break-glass flag.
if [ "${WP_ORG_DEPLOY_ENABLED:-false}" = "true" ]; then
  wp_plugin_base_require_commands "WordPress.org deploy" svn
  bash "$SCRIPT_DIR/deploy_wordpress_org.sh" "$VERSION" "$CONFIG_OVERRIDE" "$WP_PLUGIN_BASE_PACKAGE_DIR"
fi

if [ "${WOOCOMMERCE_COM_DEPLOY_ENABLED:-false}" = "true" ] && [ -n "${WOOCOMMERCE_COM_PRODUCT_ID:-}" ]; then
  bash "$SCRIPT_DIR/deploy_woocommerce_com.sh" "$VERSION" "$CONFIG_OVERRIDE" "$WP_PLUGIN_BASE_PACKAGE_ZIP"
fi
