#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOUNDATION_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_SCHEMA_PATH="$FOUNDATION_DIR/docs/config-schema.json"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

CONFIG_SCOPE="project"
CONFIG_OVERRIDE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --scope)
      if [ "$#" -lt 2 ]; then
        echo "--scope requires a value." >&2
        exit 1
      fi
      CONFIG_SCOPE="$2"
      shift 2
      ;;
    --scope=*)
      CONFIG_SCOPE="${1#*=}"
      shift
      ;;
    *)
      CONFIG_OVERRIDE="$1"
      shift
      ;;
  esac
done

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

if [ ! -f "$CONFIG_SCHEMA_PATH" ]; then
  echo "Config schema not found: $CONFIG_SCHEMA_PATH" >&2
  exit 1
fi

jq -e '.schema_version == 1 and (.keys | type == "object") and (.scopes | type == "array")' "$CONFIG_SCHEMA_PATH" >/dev/null

validate_regex() {
  local value="$1"
  local pattern="$2"
  local label="$3"

  if [[ ! "$value" =~ $pattern ]]; then
    echo "Invalid ${label}: ${value}" >&2
    exit 1
  fi
}

validate_file() {
  local relative_path="$1"
  local label="$2"
  local resolved_path

  resolved_path="$(wp_plugin_base_resolve_path "$relative_path")"
  wp_plugin_base_assert_path_within_root "$resolved_path" "$label"
  if [ ! -f "$resolved_path" ]; then
    echo "${label} not found: ${relative_path}" >&2
    exit 1
  fi
}

validate_repo_relative_paths() {
  local raw_paths="$1"
  local label="$2"
  local require_exists="${3:-false}"
  local path
  local normalized_path
  local resolved_path

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [[ "$path" = /* ]]; then
      echo "${label} must use repo-relative paths: ${path}" >&2
      exit 1
    fi
    normalized_path="$(normalize_repo_relative_path "$path")"
    if [ -z "$normalized_path" ]; then
      echo "${label} must use repo-relative paths: ${path}" >&2
      exit 1
    fi
    if [[ "$normalized_path" =~ [[:space:]] ]]; then
      echo "${label} paths must not contain whitespace: ${path}" >&2
      exit 1
    fi
    if [[ "$normalized_path" =~ [*?\[\]\{\}] ]]; then
      echo "${label} must use explicit repo-relative paths, not glob patterns: ${path}" >&2
      exit 1
    fi
    resolved_path="$(wp_plugin_base_resolve_path "$normalized_path")"
    wp_plugin_base_assert_path_within_root "$resolved_path" "$label"
    if [ "$require_exists" = "true" ] && [ ! -e "$resolved_path" ]; then
      echo "${label} path not found: ${path}" >&2
      exit 1
    fi
  done < <(wp_plugin_base_csv_to_lines "$raw_paths")
}

normalize_repo_relative_path() {
  local path="$1"
  path="${path#./}"
  path="${path#/}"
  printf '%s\n' "$path"
}

validate_distignore_path() {
  local relative_path="$1"
  local normalized_path

  validate_repo_relative_paths "$relative_path" "DISTIGNORE_FILE"
  normalized_path="$(normalize_repo_relative_path "$relative_path")"
  if [[ ! "$normalized_path" =~ (^|/)(\.distignore|[^/]+\.distignore)$ ]]; then
    echo "DISTIGNORE_FILE must point to a repo-relative *.distignore file: ${relative_path}" >&2
    exit 1
  fi
}

validate_output_path() {
  local relative_path="$1"
  local label="$2"
  local resolved_path
  local parent_dir
  local existing_dir

  resolved_path="$(wp_plugin_base_resolve_path "$relative_path")"
  wp_plugin_base_assert_path_within_root "$resolved_path" "$label"

  parent_dir="$(dirname "$resolved_path")"
  wp_plugin_base_assert_path_within_root "$parent_dir" "${label} parent directory"

  existing_dir="$parent_dir"
  while [ ! -d "$existing_dir" ] && [ "$existing_dir" != "/" ]; do
    existing_dir="$(dirname "$existing_dir")"
  done

  if [ -e "$resolved_path" ] && [ ! -f "$resolved_path" ]; then
    echo "${label} must point to a file path, not an existing non-file entry: ${relative_path}" >&2
    exit 1
  fi

  if [ ! -d "$existing_dir" ] || [ ! -w "$existing_dir" ]; then
    echo "${label} parent directory is not writable: ${relative_path}" >&2
    exit 1
  fi
}

validate_https_url() {
  local value="$1"
  local label="$2"
  local scheme
  local remainder
  local host

  scheme="${value%%://*}"
  if [ "$scheme" != "https" ]; then
    echo "Invalid ${label}: ${value}" >&2
    exit 1
  fi

  remainder="${value#*://}"
  host="${remainder%%/*}"
  if [[ ! "$host" =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ ]]; then
    echo "Invalid ${label}: ${value}" >&2
    exit 1
  fi
}

validate_url_without_secrets() {
  local value="$1"
  local label="$2"
  local remainder
  local authority

  remainder="${value#https://}"
  authority="${remainder%%/*}"
  authority="${authority%%\?*}"
  authority="${authority%%#*}"

  if [[ "$authority" = *@* ]]; then
    echo "${label} must not include URL credentials: ${value}" >&2
    exit 1
  fi

  if [[ "$value" = *\?* || "$value" = *#* ]]; then
    echo "${label} must not include query strings or fragments: ${value}" >&2
    exit 1
  fi
}

validate_public_https_url() {
  local value="$1"
  local label="$2"
  local host=""

  validate_https_url "$value" "$label"
  validate_url_without_secrets "$value" "$label"

  host="$(wp_plugin_base_url_host "$value")"
  if [ -z "$host" ]; then
    echo "Invalid ${label}: ${value}" >&2
    exit 1
  fi

  if wp_plugin_base_host_is_local_or_private "$host"; then
    echo "${label} must not use localhost, private-network, link-local, or *.internal hosts: ${host}" >&2
    exit 1
  fi
}

validate_trusted_git_host() {
  local host="$1"
  local label="$2"
  local configured_host=""

  validate_regex "$host" '^[A-Za-z0-9.-]+$' "$label"

  if wp_plugin_base_host_is_local_or_private "$host"; then
    echo "${label} must not use localhost, private-network, link-local, or *.internal hosts: ${host}" >&2
    exit 1
  fi

  if wp_plugin_base_host_is_default_trusted_git_host "$host"; then
    return
  fi

  while IFS= read -r configured_host; do
    [ -n "$configured_host" ] || continue
    if [ "$configured_host" = "$host" ]; then
      return
    fi
  done < <(wp_plugin_base_csv_to_lines "${TRUSTED_GIT_HOSTS:-}")

  echo "${label} host ${host} is not trusted. Add it to TRUSTED_GIT_HOSTS for self-managed GitHub/GitLab instances." >&2
  exit 1
}

validate_trusted_git_host_entry() {
  local host="$1"
  local label="$2"

  validate_regex "$host" '^[A-Za-z0-9.-]+$' "$label"

  if wp_plugin_base_host_is_local_or_private "$host"; then
    echo "${label} must not use localhost, private-network, link-local, or *.internal hosts: ${host}" >&2
    exit 1
  fi
}

validate_trusted_git_url() {
  local value="$1"
  local label="$2"
  local host=""

  validate_https_url "$value" "$label"
  validate_url_without_secrets "$value" "$label"
  host="$(wp_plugin_base_url_host "$value")"
  if [ -z "$host" ]; then
    echo "Invalid ${label}: ${value}" >&2
    exit 1
  fi

  validate_trusted_git_host "$host" "${label} host"
}

if ! jq -e --arg scope "$CONFIG_SCOPE" '.scopes | index($scope) != null' "$CONFIG_SCHEMA_PATH" >/dev/null; then
  echo "Unsupported config validation scope: ${CONFIG_SCOPE}" >&2
  exit 1
fi

required_keys="$(
  jq -r --arg scope "$CONFIG_SCOPE" '
    .keys
    | to_entries
    | map(select((.value.required_in_scopes // []) | index($scope) != null) | .key)
    | .[]
  ' "$CONFIG_SCHEMA_PATH"
)"

if [ -n "$required_keys" ]; then
  # shellcheck disable=SC2086
  wp_plugin_base_require_vars $required_keys
fi

if [ -n "${FOUNDATION_REPOSITORY:-}" ]; then
  validate_regex "$FOUNDATION_REPOSITORY" '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' 'FOUNDATION_REPOSITORY'
fi
validate_regex "$FOUNDATION_RELEASE_SOURCE_PROVIDER" '^(github-release|gitlab-release)$' 'FOUNDATION_RELEASE_SOURCE_PROVIDER'
validate_regex "$FOUNDATION_RELEASE_SOURCE_REFERENCE" '^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+$' 'FOUNDATION_RELEASE_SOURCE_REFERENCE'
validate_trusted_git_url "$FOUNDATION_RELEASE_SOURCE_API_BASE" 'FOUNDATION_RELEASE_SOURCE_API_BASE'
validate_regex "$FOUNDATION_VERSION" '^v[0-9]+\.[0-9]+\.[0-9]+$' 'FOUNDATION_VERSION'
validate_regex "$PRODUCTION_ENVIRONMENT" '^[A-Za-z0-9_.-]+$' 'PRODUCTION_ENVIRONMENT'
if [ -n "${FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER:-}" ]; then
  validate_trusted_git_url "$FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER" 'FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER'
fi

if [ "$FOUNDATION_RELEASE_SOURCE_PROVIDER" = "gitlab-release" ] && [ "$(wp_plugin_base_url_host "$FOUNDATION_RELEASE_SOURCE_API_BASE")" != "gitlab.com" ] && [ -z "${FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER:-}" ]; then
  echo "FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER is required for self-managed GitLab foundation sources." >&2
  exit 1
fi

if [[ "$CONFIG_SCOPE" =~ ^(project|ci|readiness|release|deploy-structure|deploy)$ ]]; then
  validate_regex "$PLUGIN_NAME" '^[^[:cntrl:]]+$' 'PLUGIN_NAME'
  validate_regex "$PLUGIN_SLUG" '^[a-z0-9][a-z0-9-]*$' 'PLUGIN_SLUG'
  validate_regex "$ZIP_FILE" '^[A-Za-z0-9][A-Za-z0-9._-]*\.zip$' 'ZIP_FILE'
  validate_regex "$PHP_VERSION" '^[0-9]+(\.[0-9]+){0,2}$' 'PHP_VERSION'
  validate_regex "$NODE_VERSION" '^[0-9]+(\.[0-9]+){0,2}$' 'NODE_VERSION'
  validate_regex "$AUTOMATION_PROVIDER" '^(github|gitlab)$' 'AUTOMATION_PROVIDER'
  validate_trusted_git_url "$AUTOMATION_API_BASE" 'AUTOMATION_API_BASE'
  validate_regex "${PHP_RUNTIME_MATRIX:-}" '^$|^[0-9]+(\.[0-9]+){0,2}(,[0-9]+(\.[0-9]+){0,2})*$' 'PHP_RUNTIME_MATRIX'
  validate_regex "$PHP_RUNTIME_MATRIX_MODE" '^(smoke|strict)$' 'PHP_RUNTIME_MATRIX_MODE'
  validate_regex "${PHPSTAN_MEMORY_LIMIT:-}" '^$|^-1$|^[1-9][0-9]*[KMGkmg]?$' 'PHPSTAN_MEMORY_LIMIT'
  validate_file "$MAIN_PLUGIN_FILE" "Main plugin file"
  validate_file "$README_FILE" "Readme file"

  if [ -n "${VERSION_CONSTANT_NAME:-}" ]; then
    validate_regex "$VERSION_CONSTANT_NAME" '^[A-Z][A-Z0-9_]*$' 'VERSION_CONSTANT_NAME'
  fi

  if [ -n "${CODEOWNERS_REVIEWERS:-}" ]; then
    validate_regex "$CODEOWNERS_REVIEWERS" '^@[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?( +@[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?)*$' 'CODEOWNERS_REVIEWERS'
  fi

  if [ -n "${WORDPRESS_ORG_SLUG:-}" ]; then
    validate_regex "$WORDPRESS_ORG_SLUG" '^[a-z0-9][a-z0-9-]*$' 'WORDPRESS_ORG_SLUG'
  fi

  if [ -n "${POT_FILE:-}" ]; then
    validate_output_path "$POT_FILE" "POT file"
  fi

  validate_distignore_path "$DISTIGNORE_FILE"

  if [ -n "${PACKAGE_INCLUDE:-}" ]; then
    validate_repo_relative_paths "$PACKAGE_INCLUDE" "PACKAGE_INCLUDE" true
  fi

  validate_repo_relative_paths "$WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE" "WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE"

  if [ -n "${PACKAGE_EXCLUDE:-}" ]; then
    validate_repo_relative_paths "$PACKAGE_EXCLUDE" "PACKAGE_EXCLUDE"
  fi

  if [ -n "${BUILD_SCRIPT:-}" ]; then
    build_script_requires_existing_path="true"
    if wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}" && [ "$BUILD_SCRIPT" = ".wp-plugin-base-admin-ui/build.sh" ]; then
      build_script_requires_existing_path="false"
    fi
    validate_repo_relative_paths "$BUILD_SCRIPT" "BUILD_SCRIPT" "$build_script_requires_existing_path"
  fi

  if [ -n "${EXTRA_ALLOWED_HOSTS:-}" ]; then
    while IFS= read -r host; do
      validate_regex "$host" '^[A-Za-z0-9.-]+$' 'EXTRA_ALLOWED_HOSTS host'
    done < <(wp_plugin_base_csv_to_lines "$EXTRA_ALLOWED_HOSTS")
  fi

  if [ -n "${TRUSTED_GIT_HOSTS:-}" ]; then
    while IFS= read -r host; do
      [ -n "$host" ] || continue
      validate_trusted_git_host_entry "$host" 'TRUSTED_GIT_HOSTS host'
    done < <(wp_plugin_base_csv_to_lines "$TRUSTED_GIT_HOSTS")
  fi

  validate_regex "$WORDPRESS_READINESS_ENABLED" '^(true|false)$' 'WORDPRESS_READINESS_ENABLED'
  validate_regex "$WORDPRESS_QUALITY_PACK_ENABLED" '^(true|false)$' 'WORDPRESS_QUALITY_PACK_ENABLED'
  validate_regex "$WORDPRESS_SECURITY_PACK_ENABLED" '^(true|false)$' 'WORDPRESS_SECURITY_PACK_ENABLED'
  validate_regex "$RELEASE_READINESS_MODE" '^(standard|security-sensitive)$' 'RELEASE_READINESS_MODE'
  validate_regex "$WOOCOMMERCE_QIT_ENABLED" '^(true|false)$' 'WOOCOMMERCE_QIT_ENABLED'
  validate_regex "${WOOCOMMERCE_COM_PRODUCT_ID:-}" '^$|^[0-9]+$' 'WOOCOMMERCE_COM_PRODUCT_ID'
  validate_regex "${WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS:-30}" '^[1-9][0-9]*$' 'WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS'
  validate_regex "${PLUGIN_RUNTIME_UPDATE_PROVIDER:-none}" '^(none|github-release|gitlab-release|generic-json)$' 'PLUGIN_RUNTIME_UPDATE_PROVIDER'
  validate_regex "${GITHUB_RELEASE_UPDATER_ENABLED:-false}" '^(true|false)$' 'GITHUB_RELEASE_UPDATER_ENABLED'
  validate_regex "${REST_OPERATIONS_PACK_ENABLED:-false}" '^(true|false)$' 'REST_OPERATIONS_PACK_ENABLED'
  validate_regex "${REST_API_NAMESPACE:-}" '^$|^[a-z0-9][a-z0-9-]*/v[0-9]+$' 'REST_API_NAMESPACE'
  validate_regex "${REST_ABILITIES_ENABLED:-false}" '^(true|false)$' 'REST_ABILITIES_ENABLED'
  validate_regex "${ADMIN_UI_PACK_ENABLED:-false}" '^(true|false)$' 'ADMIN_UI_PACK_ENABLED'
  validate_regex "${ADMIN_UI_STARTER:-}" '^$|^(basic|dataviews)$' 'ADMIN_UI_STARTER'
  validate_regex "${ADMIN_UI_EXPERIMENTAL_DATAVIEWS:-false}" '^(true|false)$' 'ADMIN_UI_EXPERIMENTAL_DATAVIEWS'
  validate_regex "${ADMIN_UI_NPM_AUDIT_LEVEL:-high}" '^(high|critical)$' 'ADMIN_UI_NPM_AUDIT_LEVEL'
  if [ -n "${GITHUB_RELEASE_UPDATER_REPO_URL:-}" ]; then
    validate_public_https_url "$GITHUB_RELEASE_UPDATER_REPO_URL" 'GITHUB_RELEASE_UPDATER_REPO_URL'
    if [[ "$GITHUB_RELEASE_UPDATER_REPO_URL" != https://github.com/* ]]; then
      echo "Invalid GITHUB_RELEASE_UPDATER_REPO_URL: ${GITHUB_RELEASE_UPDATER_REPO_URL}" >&2
      exit 1
    fi
    github_repo_path="${GITHUB_RELEASE_UPDATER_REPO_URL#https://github.com/}"
    github_repo_path="${github_repo_path%/}"
    if [[ ! "$github_repo_path" =~ ^[^/]+/[^/]+$ ]]; then
      echo "Invalid GITHUB_RELEASE_UPDATER_REPO_URL: ${GITHUB_RELEASE_UPDATER_REPO_URL}" >&2
      exit 1
    fi
  fi

  if [ -n "${PLUGIN_RUNTIME_UPDATE_SOURCE_URL:-}" ]; then
    validate_public_https_url "$PLUGIN_RUNTIME_UPDATE_SOURCE_URL" 'PLUGIN_RUNTIME_UPDATE_SOURCE_URL'
  fi

  https_scheme_regex='https:'
  case "${PLUGIN_RUNTIME_UPDATE_PROVIDER:-none}" in
    none)
      ;;
    github-release)
      if [ "${AUTOMATION_PROVIDER:-github}" != "github" ]; then
        echo "PLUGIN_RUNTIME_UPDATE_PROVIDER=github-release requires AUTOMATION_PROVIDER=github." >&2
        exit 1
      fi
      runtime_source_regex="^${https_scheme_regex}//github\\.com/[^/]+/[^/]+/?$"
      if [[ ! "${PLUGIN_RUNTIME_UPDATE_SOURCE_URL:-}" =~ $runtime_source_regex ]]; then
        echo "PLUGIN_RUNTIME_UPDATE_PROVIDER=github-release requires PLUGIN_RUNTIME_UPDATE_SOURCE_URL to use https://github.com/<owner>/<repo>." >&2
        exit 1
      fi
      validate_trusted_git_url "$PLUGIN_RUNTIME_UPDATE_SOURCE_URL" 'PLUGIN_RUNTIME_UPDATE_SOURCE_URL'
      ;;
    gitlab-release)
      if [ "${AUTOMATION_PROVIDER:-github}" != "gitlab" ]; then
        echo "PLUGIN_RUNTIME_UPDATE_PROVIDER=gitlab-release requires AUTOMATION_PROVIDER=gitlab." >&2
        exit 1
      fi
      runtime_source_regex="^${https_scheme_regex}//[A-Za-z0-9.-]+(/[^/]+)+/?$"
      if [[ ! "${PLUGIN_RUNTIME_UPDATE_SOURCE_URL:-}" =~ $runtime_source_regex ]]; then
        echo "PLUGIN_RUNTIME_UPDATE_PROVIDER=gitlab-release requires PLUGIN_RUNTIME_UPDATE_SOURCE_URL to use a GitLab project URL." >&2
        exit 1
      fi
      validate_trusted_git_url "$PLUGIN_RUNTIME_UPDATE_SOURCE_URL" 'PLUGIN_RUNTIME_UPDATE_SOURCE_URL'
      ;;
    generic-json)
      if [ -z "${PLUGIN_RUNTIME_UPDATE_SOURCE_URL:-}" ]; then
        echo "PLUGIN_RUNTIME_UPDATE_PROVIDER=generic-json requires PLUGIN_RUNTIME_UPDATE_SOURCE_URL." >&2
        exit 1
      fi
      validate_public_https_url "$PLUGIN_RUNTIME_UPDATE_SOURCE_URL" 'PLUGIN_RUNTIME_UPDATE_SOURCE_URL'
      ;;
  esac

  if wp_plugin_base_is_true "${REST_ABILITIES_ENABLED:-false}" && ! wp_plugin_base_is_true "${REST_OPERATIONS_PACK_ENABLED:-false}"; then
    echo "REST_ABILITIES_ENABLED=true requires REST_OPERATIONS_PACK_ENABLED=true." >&2
    exit 1
  fi

  if wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}" && ! wp_plugin_base_is_true "${REST_OPERATIONS_PACK_ENABLED:-false}"; then
    echo "ADMIN_UI_PACK_ENABLED=true requires REST_OPERATIONS_PACK_ENABLED=true." >&2
    exit 1
  fi

  if wp_plugin_base_is_true "${ADMIN_UI_EXPERIMENTAL_DATAVIEWS_RAW:-false}" && ! wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}"; then
    echo "ADMIN_UI_EXPERIMENTAL_DATAVIEWS=true requires ADMIN_UI_PACK_ENABLED=true." >&2
    exit 1
  fi

  if wp_plugin_base_is_true "${ADMIN_UI_STARTER_WAS_SET:-false}" && ! wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}"; then
    echo "ADMIN_UI_STARTER requires ADMIN_UI_PACK_ENABLED=true." >&2
    exit 1
  fi

  if [ "${ADMIN_UI_STARTER:-}" = "basic" ] && wp_plugin_base_is_true "${ADMIN_UI_EXPERIMENTAL_DATAVIEWS_RAW:-false}"; then
    echo "ADMIN_UI_STARTER=basic conflicts with ADMIN_UI_EXPERIMENTAL_DATAVIEWS=true. Use ADMIN_UI_STARTER=dataviews or unset the legacy flag." >&2
    exit 1
  fi

  if wp_plugin_base_is_true "${ADMIN_UI_PACK_ENABLED:-false}" && [ -z "${BUILD_SCRIPT:-}" ]; then
    echo "ADMIN_UI_PACK_ENABLED=true requires BUILD_SCRIPT to be set." >&2
    exit 1
  fi
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS:-}" '^$|^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS:-}" '^$|^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES:-}" '^$|^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES:-}" '^$|^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS:-false}" '^(true|false)$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY:-}" '^$|^[0-9]+$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY:-}" '^$|^[0-9]+$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY'
  validate_regex "${WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY:-}" '^$|^[0-9]+$' 'WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY'
  validate_regex "${PHPDOC_VERSION_REPLACEMENT_ENABLED:-false}" '^(true|false)$' 'PHPDOC_VERSION_REPLACEMENT_ENABLED'
  validate_regex "${CHANGELOG_MD_SYNC_ENABLED:-false}" '^(true|false)$' 'CHANGELOG_MD_SYNC_ENABLED'
  validate_regex "${CHANGELOG_SOURCE:-commits}" '^(commits|prs_titles|change_request_titles)$' 'CHANGELOG_SOURCE'
  validate_regex "${SIMULATE_RELEASE_WORKFLOW_ENABLED:-false}" '^(true|false)$' 'SIMULATE_RELEASE_WORKFLOW_ENABLED'
  validate_regex "${GLOTPRESS_TRIGGER_ENABLED:-false}" '^(true|false)$' 'GLOTPRESS_TRIGGER_ENABLED'
  validate_regex "${GLOTPRESS_FAIL_ON_ERROR:-false}" '^(true|false)$' 'GLOTPRESS_FAIL_ON_ERROR'
  validate_regex "${DEPLOY_NOTIFICATION_ENABLED:-false}" '^(true|false)$' 'DEPLOY_NOTIFICATION_ENABLED'

  if wp_plugin_base_is_true "${GLOTPRESS_TRIGGER_ENABLED:-false}"; then
    if [ -z "${GLOTPRESS_URL:-}" ] || [ -z "${GLOTPRESS_PROJECT_SLUG:-}" ]; then
      echo "GLOTPRESS_TRIGGER_ENABLED=true requires GLOTPRESS_URL and GLOTPRESS_PROJECT_SLUG." >&2
      exit 1
    fi
    validate_public_https_url "$GLOTPRESS_URL" "GLOTPRESS_URL"
    validate_regex "$GLOTPRESS_PROJECT_SLUG" '^[A-Za-z0-9][A-Za-z0-9._/-]*$' 'GLOTPRESS_PROJECT_SLUG'
    if [[ "$GLOTPRESS_PROJECT_SLUG" = *..* || "$GLOTPRESS_PROJECT_SLUG" = *//* || "$GLOTPRESS_PROJECT_SLUG" = */ ]]; then
      echo "Invalid GLOTPRESS_PROJECT_SLUG: ${GLOTPRESS_PROJECT_SLUG}" >&2
      exit 1
    fi
  elif [ -n "${GLOTPRESS_URL:-}" ]; then
    validate_public_https_url "$GLOTPRESS_URL" "GLOTPRESS_URL"
  fi

  if wp_plugin_base_is_true "$WORDPRESS_QUALITY_PACK_ENABLED" && ! wp_plugin_base_is_true "$WORDPRESS_READINESS_ENABLED"; then
    echo "WORDPRESS_QUALITY_PACK_ENABLED=true requires WORDPRESS_READINESS_ENABLED=true." >&2
    exit 1
  fi

  if wp_plugin_base_is_true "$WORDPRESS_SECURITY_PACK_ENABLED" && ! wp_plugin_base_is_true "$WORDPRESS_READINESS_ENABLED"; then
    echo "WORDPRESS_SECURITY_PACK_ENABLED=true requires WORDPRESS_READINESS_ENABLED=true." >&2
    exit 1
  fi

  if [ "${RELEASE_READINESS_MODE:-standard}" = "security-sensitive" ]; then
    if ! wp_plugin_base_is_true "$WORDPRESS_READINESS_ENABLED" || ! wp_plugin_base_is_true "$WORDPRESS_QUALITY_PACK_ENABLED" || ! wp_plugin_base_is_true "$WORDPRESS_SECURITY_PACK_ENABLED"; then
      echo "RELEASE_READINESS_MODE=security-sensitive requires WORDPRESS_READINESS_ENABLED=true, WORDPRESS_QUALITY_PACK_ENABLED=true, and WORDPRESS_SECURITY_PACK_ENABLED=true." >&2
      exit 1
    fi

    if ! wp_plugin_base_is_true "${WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS:-false}"; then
      echo "RELEASE_READINESS_MODE=security-sensitive requires WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS=true." >&2
      exit 1
    fi

    if [ "${ADMIN_UI_NPM_AUDIT_LEVEL:-high}" != "high" ]; then
      echo "RELEASE_READINESS_MODE=security-sensitive requires ADMIN_UI_NPM_AUDIT_LEVEL=high." >&2
      exit 1
    fi

    if [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS:-}" ] || [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS:-}" ] || [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES:-}" ] || [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES:-}" ] || [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY:-}" ] || [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY:-}" ] || [ -n "${WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY:-}" ]; then
      echo "RELEASE_READINESS_MODE=security-sensitive requires full Plugin Check coverage. Clear WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS, WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS, WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES, WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES, and severity overrides." >&2
      exit 1
    fi
  fi

  if [ "${PLUGIN_RUNTIME_UPDATE_PROVIDER:-none}" != "none" ] && [ -z "${PLUGIN_RUNTIME_UPDATE_SOURCE_URL:-}" ]; then
    echo "PLUGIN_RUNTIME_UPDATE_PROVIDER=${PLUGIN_RUNTIME_UPDATE_PROVIDER} requires PLUGIN_RUNTIME_UPDATE_SOURCE_URL." >&2
    exit 1
  fi

  if wp_plugin_base_is_true "${GITHUB_RELEASE_UPDATER_ENABLED:-false}" && [ -z "${GITHUB_RELEASE_UPDATER_REPO_URL:-}" ]; then
    echo "GITHUB_RELEASE_UPDATER_ENABLED=true requires GITHUB_RELEASE_UPDATER_REPO_URL." >&2
    exit 1
  fi
fi

echo "Validated ${CONFIG_PATH} for scope ${CONFIG_SCOPE}."
