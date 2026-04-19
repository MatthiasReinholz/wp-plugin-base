#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

DEPENDENCY_ID="${1:-}"
OUTPUT_PATH="${2:-${GITHUB_OUTPUT:-}}"

if [ -z "$DEPENDENCY_ID" ]; then
  echo "Usage: $0 <dependency-id> [output-path]" >&2
  exit 1
fi

wp_plugin_base_require_commands "external dependency update preparation" curl jq perl awk sed tar mktemp

if command -v sha256sum >/dev/null 2>&1; then
  SHA256_BIN='sha256sum'
elif command -v shasum >/dev/null 2>&1; then
  SHA256_BIN='shasum -a 256'
else
  echo "A SHA-256 tool is required (sha256sum or shasum)." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

emit_output() {
  local key="$1"
  local value="$2"
  if [ -n "$OUTPUT_PATH" ]; then
    printf '%s=%s\n' "$key" "$value" >> "$OUTPUT_PATH"
  else
    printf '%s=%s\n' "$key" "$value"
  fi
}

emit_defaults() {
  emit_output "update_needed" "false"
  emit_output "dependency_id" "$DEPENDENCY_ID"
  emit_output "branch_name" ""
  emit_output "pr_title" ""
  emit_output "commit_message" ""
  emit_output "pr_body_file" ""
  emit_output "git_add_paths" ""
  emit_output "from_version" ""
  emit_output "to_version" ""
}

compute_sha256() {
  local file="$1"
  if [ "$SHA256_BIN" = "sha256sum" ]; then
    sha256sum "$file" | awk '{print $1}'
    return
  fi

  shasum -a 256 "$file" | awk '{print $1}'
}

github_api_get() {
  local url="$1"

  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL \
      --connect-timeout 10 \
      --max-time 60 \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url"
    return
  fi

  curl -fsSL \
    --connect-timeout 10 \
    --max-time 60 \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$url"
}

github_fetch_release_list() {
  local repository="$1"
  local page=1
  local releases_json='[]'

  while :; do
    local page_json
    page_json="$(wp_plugin_base_run_with_retry 3 2 "Fetch releases for ${repository} page ${page}" github_api_get "https://api.github.com/repos/${repository}/releases?per_page=100&page=${page}")"

    releases_json="$(
      jq -s '.[0] + .[1]' \
        <(printf '%s\n' "$releases_json") \
        <(printf '%s\n' "$page_json")
    )"

    local page_count
    page_count="$(printf '%s\n' "$page_json" | jq 'length')"
    if [ "$page_count" -lt 100 ]; then
      break
    fi

    page=$((page + 1))
  done

  printf '%s\n' "$releases_json"
}

github_latest_semver() {
  local repository="$1"
  local major_filter="${2:-}"
  local releases_json

  releases_json="$(github_fetch_release_list "$repository")"
  printf '%s\n' "$releases_json" | jq -r --arg major_filter "$major_filter" '
    def semver_parts:
      capture("^(?:v)?(?<major>[0-9]+)\\.(?<minor>[0-9]+)(?:\\.(?<patch>[0-9]+))?$")
      | [(.major | tonumber), (.minor | tonumber), ((.patch // "0") | tonumber)];
    map(
      select(
        .draft == false and
        .prerelease == false and
        (.tag_name | test("^v?[0-9]+\\.[0-9]+(\\.[0-9]+)?$")) and
        (
          $major_filter == "" or
          ((.tag_name | ltrimstr("v") | split(".")[0]) == $major_filter)
        )
      )
    )
    | map(.tag_name | ltrimstr("v"))
    | sort_by(semver_parts)
    | last // ""
  '
}

compare_semver() {
  local left="$1"
  local right="$2"
  local left_parts right_parts
  local i

  IFS='.' read -r -a left_parts <<<"$left"
  IFS='.' read -r -a right_parts <<<"$right"

  for i in 0 1 2; do
    local l="${left_parts[$i]:-0}"
    local r="${right_parts[$i]:-0}"
    if [ "$l" -gt "$r" ]; then
      echo 1
      return
    fi
    if [ "$l" -lt "$r" ]; then
      echo -1
      return
    fi
  done

  echo 0
}

replace_variable_assignment() {
  local file="$1"
  local variable="$2"
  local value="$3"

  perl -0pi -e "s/^${variable}='[^']*'\$/${variable}='${value}'/m" "$file"
}

replace_ordered_single_quoted_values() {
  local file="$1"
  local needle="$2"
  shift 2
  local values=("$@")
  local serialized

  if [ "${#values[@]}" -eq 0 ]; then
    echo "No replacement values provided for $needle" >&2
    exit 1
  fi

  serialized="$(printf '%s\n' "${values[@]}")"

  awk -v needle="$needle" -v values="$serialized" '
    BEGIN {
      count = split(values, replacements, "\n")
      idx = 1
    }
    {
      if (index($0, needle) > 0) {
        if (idx > count) {
          printf "Too many matches for %s in %s\n", needle, FILENAME > "/dev/stderr"
          exit 2
        }
        if (sub(/\047[^\047]*\047/, sprintf("\047%s\047", replacements[idx])) == 0) {
          printf "Unable to replace value for %s in %s\n", needle, FILENAME > "/dev/stderr"
          exit 2
        }
        idx++
      }
      print
    }
    END {
      if (idx - 1 != count) {
        printf "Expected %d matches for %s in %s, saw %d\n", count, needle, FILENAME, idx - 1 > "/dev/stderr"
        exit 2
      }
    }
  ' "$file" > "$file.tmp"

  mv "$file.tmp" "$file"
}

prepare_pr_body() {
  local body_file="$1"
  local dependency_name="$2"
  local source_repository="$3"
  local current_version="$4"
  local target_version="$5"
  local dependency_purpose="$6"
  local trust_mode="$7"
  local trust_checks="$8"

  WP_PLUGIN_BASE_DEPENDENCY_NAME="$dependency_name" \
  WP_PLUGIN_BASE_DEPENDENCY_SOURCE_REPOSITORY="$source_repository" \
  WP_PLUGIN_BASE_DEPENDENCY_CURRENT_VERSION="$current_version" \
  WP_PLUGIN_BASE_DEPENDENCY_TARGET_VERSION="$target_version" \
  WP_PLUGIN_BASE_DEPENDENCY_PURPOSE="$dependency_purpose" \
  WP_PLUGIN_BASE_DEPENDENCY_TRUST_MODE="$trust_mode" \
  WP_PLUGIN_BASE_DEPENDENCY_TRUST_CHECKS="$trust_checks" \
    bash "$SCRIPT_DIR/write_external_github_dependency_pr_body.sh" "$body_file"
}

dockerhub_composer_v2_digest() {
  local token
  token="$(curl -fsSL 'https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/composer:pull' | jq -r '.token // ""')"
  if [ -z "$token" ]; then
    echo "Unable to resolve Docker Hub registry token for library/composer." >&2
    exit 1
  fi

  local digest
  digest="$(curl -fsSI \
    --connect-timeout 10 \
    --max-time 60 \
    -H "Authorization: Bearer ${token}" \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.index.v1+json' \
    'https://registry-1.docker.io/v2/library/composer/manifests/2' \
    | tr -d '\r' \
    | awk 'tolower($1) == "docker-content-digest:" {print $2; exit}')"

  if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "Unable to resolve Docker Hub digest for library/composer:2" >&2
    exit 1
  fi

  printf '%s\n' "$digest"
}

emit_update_outputs() {
  local branch_name="$1"
  local pr_title="$2"
  local commit_message="$3"
  local body_file="$4"
  local git_add_paths="$5"
  local from_version="$6"
  local to_version="$7"

  emit_output "update_needed" "true"
  emit_output "dependency_id" "$DEPENDENCY_ID"
  emit_output "branch_name" "$branch_name"
  emit_output "pr_title" "$pr_title"
  emit_output "commit_message" "$commit_message"
  emit_output "pr_body_file" "$body_file"
  emit_output "git_add_paths" "$git_add_paths"
  emit_output "from_version" "$from_version"
  emit_output "to_version" "$to_version"
}

prepare_plugin_check_update() {
  local current_version
  current_version="$(sed -n "s/^WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION='\([0-9][0-9.]*\)'$/\1/p" "$ROOT_DIR/scripts/lib/wordpress_tooling.sh")"

  if [ -z "$current_version" ]; then
    echo "Unable to resolve WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION." >&2
    exit 1
  fi

  local resolver_output="$TMP_DIR/plugin-check-resolution.out"
  WP_PLUGIN_BASE_PLUGIN_CHECK_ALLOWED_RELEASE_AUTHORS='davidperezgar' \
  WP_PLUGIN_BASE_PLUGIN_CHECK_MIN_RELEASE_AGE_DAYS='7' \
    bash "$SCRIPT_DIR/resolve_latest_plugin_check_version.sh" "$current_version" 'WordPress/plugin-check' "$resolver_output"

  local update_needed latest_version
  update_needed="$(sed -n 's/^update_needed=//p' "$resolver_output")"
  latest_version="$(sed -n 's/^version=//p' "$resolver_output")"

  if [ "$update_needed" != 'true' ] || [ -z "$latest_version" ]; then
    emit_defaults
    return
  fi

  if [ "$(compare_semver "$latest_version" "$current_version")" -le 0 ]; then
    emit_defaults
    return
  fi

  replace_variable_assignment "$ROOT_DIR/scripts/lib/wordpress_tooling.sh" 'WP_PLUGIN_BASE_PLUGIN_CHECK_VERSION' "$latest_version"

  local body_file="${RUNNER_TEMP:-$TMP_DIR}/plugin-check-update-pr.md"
  prepare_pr_body \
    "$body_file" \
    'plugin-check' \
    'WordPress/plugin-check' \
    "$current_version" \
    "$latest_version" \
    'used by WordPress readiness validation' \
    'metadata-only' \
    $'selected from published, non-draft, non-prerelease releases\nconstrained to the current major version series\nrelease author matched the reviewed allowlist\nrelease satisfied the 7-day stabilization window before automation\nversion pin updated in scripts/lib/wordpress_tooling.sh'

  emit_update_outputs \
    "chore/update-plugin-check-${latest_version}" \
    "chore: update plugin-check to ${latest_version}" \
    "chore: update plugin-check to ${latest_version}" \
    "$body_file" \
    'scripts/lib/wordpress_tooling.sh' \
    "$current_version" \
    "$latest_version"
}

prepare_puc_runtime_update() {
  local runtime_file="$ROOT_DIR/templates/child/github-release-updater-pack/lib/wp-plugin-base/plugin-update-checker/plugin-update-checker.php"
  local current_version
  current_version="$(sed -n 's/^ \* Plugin Update Checker Library \([0-9][0-9.]*\)$/\1/p' "$runtime_file")"

  if [ -z "$current_version" ]; then
    echo "Unable to resolve current plugin-update-checker runtime version." >&2
    exit 1
  fi

  local latest_version
  latest_version="$(github_latest_semver 'YahnisElsts/plugin-update-checker' "${current_version%%.*}")"

  if [ -z "$latest_version" ] || [ "$(compare_semver "$latest_version" "$current_version")" -le 0 ]; then
    emit_defaults
    return
  fi

  local tarball_url="https://github.com/YahnisElsts/plugin-update-checker/archive/refs/tags/v${latest_version}.tar.gz"
  local tarball_path="$TMP_DIR/plugin-update-checker-v${latest_version}.tar.gz"
  curl -fsSLo "$tarball_path" "$tarball_url"
  local tarball_sha
  tarball_sha="$(compute_sha256 "$tarball_path")"

  tar -xzf "$tarball_path" -C "$TMP_DIR"

  local extracted_dir="$TMP_DIR/plugin-update-checker-${latest_version}"
  if [ ! -d "$extracted_dir" ]; then
    echo "Unexpected plugin-update-checker archive layout for version ${latest_version}." >&2
    exit 1
  fi

  local target_dir="$ROOT_DIR/templates/child/github-release-updater-pack/lib/wp-plugin-base/plugin-update-checker"
  rm -rf "$target_dir"
  mv "$extracted_dir" "$target_dir"

  perl -0pi -e "s/(currently vendors \\x60YahnisElsts\\/plugin-update-checker\\x60 \\x60)v[0-9]+\\.[0-9]+(?:\\.[0-9]+)?(\\x60\\.)/\${1}v${latest_version}\${2}/" "$ROOT_DIR/docs/distribution-runtime-updater.md"
  perl -0pi -e "s#\\[v[0-9]+\\.[0-9]+(?:\\.[0-9]+)? tar\\.gz\\]\\(https://github.com/YahnisElsts/plugin-update-checker/archive/refs/tags/v[0-9]+\\.[0-9]+(?:\\.[0-9]+)?\\.tar\\.gz\\)#[v${latest_version} tar.gz](https://github.com/YahnisElsts/plugin-update-checker/archive/refs/tags/v${latest_version}.tar.gz)#" "$ROOT_DIR/docs/distribution-runtime-updater.md"
  perl -0pi -e "s/- SHA256: \\x60[0-9a-f]{64}\\x60/- SHA256: \\x60${tarball_sha}\\x60/" "$ROOT_DIR/docs/distribution-runtime-updater.md"
  perl -0pi -e "s/(Plugin Update Checker Library )[0-9]+\\.[0-9]+(?:\\.[0-9]+)?/\${1}${latest_version}/" "$ROOT_DIR/docs/dependency-inventory.json"

  if ! grep -Fq "v${latest_version} tar.gz" "$ROOT_DIR/docs/distribution-runtime-updater.md"; then
    echo "Failed to update plugin-update-checker tarball version reference in docs/distribution-runtime-updater.md" >&2
    exit 1
  fi
  if ! grep -Fq "$tarball_sha" "$ROOT_DIR/docs/distribution-runtime-updater.md"; then
    echo "Failed to update plugin-update-checker tarball SHA256 in docs/distribution-runtime-updater.md" >&2
    exit 1
  fi
  if ! grep -Fq "Plugin Update Checker Library ${latest_version}" "$ROOT_DIR/docs/dependency-inventory.json"; then
    echo "Failed to update plugin-update-checker version pin in docs/dependency-inventory.json" >&2
    exit 1
  fi

  local body_file="${RUNNER_TEMP:-$TMP_DIR}/plugin-update-checker-runtime-update-pr.md"
  prepare_pr_body \
    "$body_file" \
    'plugin-update-checker-runtime' \
    'YahnisElsts/plugin-update-checker' \
    "$current_version" \
    "$latest_version" \
    'used by the opt-in GitHub Release updater runtime pack' \
    'metadata-only' \
    $'selected from published, non-draft, non-prerelease releases\nvendored runtime refreshed from the upstream release tarball\nrelease tarball SHA256 pinned in docs/distribution-runtime-updater.md\ndependency inventory pin pattern refreshed'

  emit_update_outputs \
    "chore/update-plugin-update-checker-${latest_version}" \
    "chore: update plugin-update-checker runtime to v${latest_version}" \
    "chore: update plugin-update-checker runtime to v${latest_version}" \
    "$body_file" \
    'templates/child/github-release-updater-pack/lib/wp-plugin-base/plugin-update-checker,docs/distribution-runtime-updater.md,docs/dependency-inventory.json' \
    "$current_version" \
    "$latest_version"
}

prepare_lint_binary_update() {
  local dependency_name="$1"
  local repository="$2"
  local version_variable="$3"
  local sha_variable="$4"
  local linux_asset_template="$5"
  local darwin_amd64_asset_template="$6"
  local darwin_arm64_asset_template="$7"

  local install_script="$ROOT_DIR/scripts/ci/install_lint_tools.sh"
  local current_version
  current_version="$(sed -n "s/^${version_variable}='\([0-9][0-9.]*\)'$/\1/p" "$install_script")"
  if [ -z "$current_version" ]; then
    echo "Unable to resolve ${version_variable} in install_lint_tools.sh" >&2
    exit 1
  fi

  local latest_version
  latest_version="$(github_latest_semver "$repository" "${current_version%%.*}")"
  if [ -z "$latest_version" ] || [ "$(compare_semver "$latest_version" "$current_version")" -le 0 ]; then
    emit_defaults
    return
  fi

  local linux_asset darwin_amd64_asset darwin_arm64_asset
  linux_asset="${linux_asset_template//\{version\}/$latest_version}"
  darwin_amd64_asset="${darwin_amd64_asset_template//\{version\}/$latest_version}"
  darwin_arm64_asset="${darwin_arm64_asset_template//\{version\}/$latest_version}"

  local linux_sha darwin_amd64_sha darwin_arm64_sha
  curl -fsSLo "$TMP_DIR/$linux_asset" "https://github.com/${repository}/releases/download/v${latest_version}/${linux_asset}"
  linux_sha="$(compute_sha256 "$TMP_DIR/$linux_asset")"

  curl -fsSLo "$TMP_DIR/$darwin_amd64_asset" "https://github.com/${repository}/releases/download/v${latest_version}/${darwin_amd64_asset}"
  darwin_amd64_sha="$(compute_sha256 "$TMP_DIR/$darwin_amd64_asset")"

  curl -fsSLo "$TMP_DIR/$darwin_arm64_asset" "https://github.com/${repository}/releases/download/v${latest_version}/${darwin_arm64_asset}"
  darwin_arm64_sha="$(compute_sha256 "$TMP_DIR/$darwin_arm64_asset")"

  replace_variable_assignment "$install_script" "$version_variable" "$latest_version"
  replace_ordered_single_quoted_values "$install_script" "${sha_variable}='" "$linux_sha" "$darwin_amd64_sha" "$darwin_arm64_sha"

  local body_file="${RUNNER_TEMP:-$TMP_DIR}/${dependency_name}-update-pr.md"
  prepare_pr_body \
    "$body_file" \
    "$dependency_name" \
    "$repository" \
    "$current_version" \
    "$latest_version" \
    'used by foundation lint and security tool bootstrap' \
    'metadata-only' \
    $'selected from published, non-draft, non-prerelease releases\nrelease archives downloaded for Linux + macOS targets\nSHA256 pins refreshed in scripts/ci/install_lint_tools.sh'

  emit_update_outputs \
    "chore/update-${dependency_name}-${latest_version}" \
    "chore: update ${dependency_name} to v${latest_version}" \
    "chore: update ${dependency_name} to v${latest_version}" \
    "$body_file" \
    'scripts/ci/install_lint_tools.sh' \
    "$current_version" \
    "$latest_version"
}

prepare_release_security_binary_update() {
  local dependency_name="$1"
  local repository="$2"
  local version_variable="$3"
  local sha_variable="$4"
  local asset_template="$5"

  local install_script="$ROOT_DIR/scripts/release/install_release_security_tools.sh"
  local current_version
  current_version="$(sed -n "s/^${version_variable}='\([0-9][0-9.]*\)'$/\1/p" "$install_script")"
  if [ -z "$current_version" ]; then
    echo "Unable to resolve ${version_variable} in install_release_security_tools.sh" >&2
    exit 1
  fi

  local latest_version
  latest_version="$(github_latest_semver "$repository" "${current_version%%.*}")"
  if [ -z "$latest_version" ] || [ "$(compare_semver "$latest_version" "$current_version")" -le 0 ]; then
    emit_defaults
    return
  fi

  local asset
  asset="${asset_template//\{version\}/$latest_version}"

  curl -fsSLo "$TMP_DIR/$asset" "https://github.com/${repository}/releases/download/v${latest_version}/${asset}"
  local asset_sha
  asset_sha="$(compute_sha256 "$TMP_DIR/$asset")"

  replace_variable_assignment "$install_script" "$version_variable" "$latest_version"
  replace_ordered_single_quoted_values "$install_script" "${sha_variable}='" "$asset_sha"

  local body_file="${RUNNER_TEMP:-$TMP_DIR}/${dependency_name}-update-pr.md"
  prepare_pr_body \
    "$body_file" \
    "$dependency_name" \
    "$repository" \
    "$current_version" \
    "$latest_version" \
    'used by release security tooling bootstrap' \
    'metadata-only' \
    $'selected from published, non-draft, non-prerelease releases\nrelease archive downloaded for Linux/x86_64 runner target\nSHA256 pin refreshed in scripts/release/install_release_security_tools.sh'

  emit_update_outputs \
    "chore/update-${dependency_name}-${latest_version}" \
    "chore: update ${dependency_name} to v${latest_version}" \
    "chore: update ${dependency_name} to v${latest_version}" \
    "$body_file" \
    'scripts/release/install_release_security_tools.sh' \
    "$current_version" \
    "$latest_version"
}

prepare_composer_image_update() {
  local tooling_script="$ROOT_DIR/scripts/lib/wordpress_tooling.sh"
  local current_value
  current_value="$(sed -n "s/^WP_PLUGIN_BASE_COMPOSER_IMAGE='\(composer@sha256:[0-9a-f]\{64\}\)'$/\1/p" "$tooling_script")"

  if [ -z "$current_value" ]; then
    echo "Unable to resolve WP_PLUGIN_BASE_COMPOSER_IMAGE from scripts/lib/wordpress_tooling.sh" >&2
    exit 1
  fi

  local current_digest
  current_digest="${current_value#composer@}"
  local latest_digest
  latest_digest="$(dockerhub_composer_v2_digest)"

  if [ "$latest_digest" = "$current_digest" ]; then
    emit_defaults
    return
  fi

  perl -0pi -e "s/^WP_PLUGIN_BASE_COMPOSER_IMAGE='composer@sha256:[0-9a-f]{64}'\$/WP_PLUGIN_BASE_COMPOSER_IMAGE='composer@${latest_digest}'/m" "$tooling_script"

  local body_file="${RUNNER_TEMP:-$TMP_DIR}/composer-docker-image-update-pr.md"
  prepare_pr_body \
    "$body_file" \
    'composer-docker-image' \
    'docker.io/library/composer' \
    "$current_digest" \
    "$latest_digest" \
    'used by WordPress readiness composer runtime' \
    'metadata-only' \
    $'selected from Docker Hub registry metadata for library/composer:2\nmanifest-list digest refreshed from registry-1.docker.io\nimage pin updated in scripts/lib/wordpress_tooling.sh'

  emit_update_outputs \
    "chore/update-composer-image-${latest_digest#sha256:}" \
    "chore: update composer docker image digest" \
    "chore: update composer docker image digest" \
    "$body_file" \
    'scripts/lib/wordpress_tooling.sh' \
    "$current_digest" \
    "$latest_digest"
}

case "$DEPENDENCY_ID" in
  plugin-check)
    prepare_plugin_check_update
    ;;
  plugin-update-checker-runtime)
    prepare_puc_runtime_update
    ;;
  shellcheck-binary)
    prepare_lint_binary_update \
      'shellcheck-binary' \
      'koalaman/shellcheck' \
      'SHELLCHECK_VERSION' \
      'shellcheck_sha256' \
      'shellcheck-v{version}.linux.x86_64.tar.xz' \
      'shellcheck-v{version}.darwin.x86_64.tar.xz' \
      'shellcheck-v{version}.darwin.aarch64.tar.xz'
    ;;
  actionlint-binary)
    prepare_lint_binary_update \
      'actionlint-binary' \
      'rhysd/actionlint' \
      'ACTIONLINT_VERSION' \
      'actionlint_sha256' \
      'actionlint_{version}_linux_amd64.tar.gz' \
      'actionlint_{version}_darwin_amd64.tar.gz' \
      'actionlint_{version}_darwin_arm64.tar.gz'
    ;;
  editorconfig-checker-binary)
    prepare_lint_binary_update \
      'editorconfig-checker-binary' \
      'editorconfig-checker/editorconfig-checker' \
      'EDITORCONFIG_CHECKER_VERSION' \
      'editorconfig_checker_sha256' \
      'editorconfig-checker-linux-amd64.tar.gz' \
      'editorconfig-checker-darwin-all.tar.gz' \
      'editorconfig-checker-darwin-all.tar.gz'
    ;;
  gitleaks-binary)
    prepare_lint_binary_update \
      'gitleaks-binary' \
      'gitleaks/gitleaks' \
      'GITLEAKS_VERSION' \
      'gitleaks_sha256' \
      'gitleaks_{version}_linux_x64.tar.gz' \
      'gitleaks_{version}_darwin_x64.tar.gz' \
      'gitleaks_{version}_darwin_arm64.tar.gz'
    ;;
  syft-binary)
    prepare_release_security_binary_update \
      'syft-binary' \
      'anchore/syft' \
      'SYFT_VERSION' \
      'syft_sha256' \
      'syft_{version}_linux_amd64.tar.gz'
    ;;
  cosign-binary)
    prepare_release_security_binary_update \
      'cosign-binary' \
      'sigstore/cosign' \
      'COSIGN_VERSION' \
      'cosign_sha256' \
      'cosign-linux-amd64'
    ;;
  composer-docker-image)
    prepare_composer_image_update
    ;;
  *)
    echo "Unsupported dependency id: $DEPENDENCY_ID" >&2
    exit 1
    ;;
esac
