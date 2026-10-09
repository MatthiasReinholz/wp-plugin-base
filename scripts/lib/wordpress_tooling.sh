#!/usr/bin/env bash

set -euo pipefail

WP_PLUGIN_BASE_COMPOSER_IMAGE='composer@sha256:9715c7f69044da2a212a5fbde29ee7da24e364d426560ae6367b060236f847d7'
WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION='2.1.0'

wp_plugin_base_wordpress_tools_dir() {
  local script_dir

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
  (cd "$script_dir/../../tools/wordpress-env" && pwd)
}

# Callers provide a private, empty directory; no partially qualified tool is activated.
wp_plugin_base_install_wordpress_env() (
  local destination_dir="$1"
  local source_dir staging_dir

  source_dir="$(wp_plugin_base_wordpress_tools_dir)" || return 1
  if [ -L "$destination_dir" ] || [ ! -d "$destination_dir" ] || \
    [ -n "$(find "$destination_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    echo 'WordPress tooling destination must be a private empty physical directory.' >&2
    return 1
  fi
  destination_dir="$(cd "$destination_dir" && pwd -P)" || return 1
  staging_dir="$(mktemp -d "${destination_dir}.staging.XXXXXX")" || return 1
  trap 'rm -rf "$staging_dir"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  cp "$source_dir/.npmrc" "$source_dir/package.json" "$source_dir/package-lock.json" "$staging_dir/" || return 1
  (
    cd "$staging_dir" || return 1
    npm ci --no-audit --no-fund >/dev/null || return $?
    node "$source_dir/../../scripts/lib/patch_wordpress_env_git.cjs" "$staging_dir" || return $?
  ) || return $?
  node - "$staging_dir" "$destination_dir" <<'NODE'
const fs = require('node:fs');
const [source, destination] = process.argv.slice(2);
const target = fs.lstatSync(destination);
if (target.isSymbolicLink() || !target.isDirectory() || fs.readdirSync(destination).length) {
  throw new Error('WordPress tooling activation requires the original empty directory');
}
// rename fails instead of nesting or replacing a newly populated destination.
fs.renameSync(source, destination);
NODE
)

# The caller owns this isolated directory and must remove it on exit.
wp_plugin_base_install_npm_audit() {
  local destination_dir="$1"
  local source_dir

  source_dir="$(wp_plugin_base_wordpress_tools_dir)/../npm-audit" || return 1
  cp "$source_dir/.npmrc" "$source_dir/package.json" "$source_dir/package-lock.json" "$destination_dir/" || return 1
  npm ci --prefix="$destination_dir" --ignore-scripts --bin-links=false --engine-strict \
    --include=dev --include=optional --include=peer --workspaces=false --global=false \
    --registry=https://registry.npmjs.org --no-audit --no-fund >/dev/null || return $?
}

wp_plugin_base_wordpress_env() {
  local install_dir="$1"
  shift
  "$install_dir/node_modules/.bin/wp-env" "$@"
}

# Only call for an environment whose home/config/tool directories this task created.
# Preserve every recovery input when Docker cleanup fails; never discard its identity.
wp_plugin_base_cleanup_temporary_wordpress_env() {
  local install_dir="$1"
  local environment_home="$2"
  local environment_config="$3"
  local npm_cache_dir="$4"
  local buildx_config_dir="$5"
  local start_attempted="$6"
  shift 6

  if [ "$start_attempted" = true ]; then
    if ! WP_ENV_HOME="$environment_home" BUILDX_CONFIG="$buildx_config_dir" NPM_CONFIG_CACHE="$npm_cache_dir" \
      wp_plugin_base_wordpress_env "$install_dir" cleanup --force --config="$environment_config" >/dev/null 2>&1; then
      echo "Temporary WordPress environment cleanup failed; retaining configuration and tools for recovery." >&2
      printf 'Retry: WP_ENV_HOME=%q BUILDX_CONFIG=%q NPM_CONFIG_CACHE=%q %q cleanup --force --config=%q\n' \
        "$environment_home" "$buildx_config_dir" "$npm_cache_dir" "$install_dir/node_modules/.bin/wp-env" "$environment_config" >&2
      return 1
    fi
  fi

  rm -rf "$environment_home" "$environment_config" "$install_dir" "$npm_cache_dir" "$buildx_config_dir" "$@"
}

wp_plugin_base_wordpress_env_start_with_retry() {
  local install_dir="$1"
  shift

  local max_attempts="${WP_PLUGIN_BASE_WP_ENV_START_ATTEMPTS:-3}"
  local attempt=1
  local retry_delay="${WP_PLUGIN_BASE_WP_ENV_RETRY_DELAY_SECONDS:-5}"
  local start_log

  start_log="$(mktemp)"

  while [ "$attempt" -le "$max_attempts" ]; do
    : > "$start_log"

    if wp_plugin_base_wordpress_env "$install_dir" start "$@" >/dev/null 2>"$start_log"; then
      rm -f "$start_log"
      return 0
    fi

    echo "wp-env start attempt ${attempt}/${max_attempts} failed; retrying." >&2
    if [ -s "$start_log" ]; then
      echo "wp-env start stderr (attempt ${attempt}/${max_attempts}):" >&2
      cat "$start_log" >&2
    fi

    wp_plugin_base_wordpress_env "$install_dir" stop "$@" >/dev/null 2>&1 || true

    attempt=$((attempt + 1))
    if [ "$attempt" -le "$max_attempts" ]; then
      sleep "$retry_delay"
    fi
  done

  rm -f "$start_log"
  echo "Failed to start wp-env after ${max_attempts} attempts." >&2
  return 1
}
