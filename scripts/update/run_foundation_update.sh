#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

CONFIG_OVERRIDE="${1:-${WP_PLUGIN_BASE_CONFIG:-.wp-plugin-base.env}}"
BASE_BRANCH="${2:-main}"

wp_plugin_base_require_commands "foundation update automation" git rsync awk paste perl mktemp
wp_plugin_base_load_config "$CONFIG_OVERRIDE"
wp_plugin_base_require_vars FOUNDATION_VERSION FOUNDATION_RELEASE_SOURCE_PROVIDER FOUNDATION_RELEASE_SOURCE_REFERENCE FOUNDATION_RELEASE_SOURCE_API_BASE

AUTOMATION_PROVIDER="${AUTOMATION_PROVIDER:-github}"
AUTOMATION_API_BASE="${AUTOMATION_API_BASE:-$(wp_plugin_base_provider_default_api_base "$AUTOMATION_PROVIDER")}"

latest_output="$(mktemp)"
verify_output="$(mktemp)"
verify_log="$(mktemp)"
body_file="$(mktemp)"
foundation_dir="$(mktemp -d)"

cleanup() {
  rm -f "$latest_output" "$verify_output" "$verify_log" "$body_file"
  rm -rf "$foundation_dir"
}
trap cleanup EXIT

bash "$SCRIPT_DIR/resolve_latest_foundation_version.sh" \
  "$FOUNDATION_VERSION" \
  "$FOUNDATION_RELEASE_SOURCE_REFERENCE" \
  "$latest_output" \
  "$FOUNDATION_RELEASE_SOURCE_PROVIDER" \
  "$FOUNDATION_RELEASE_SOURCE_API_BASE"

update_needed="$(grep '^update_needed=' "$latest_output" | cut -d= -f2-)"
if [ "$update_needed" != "true" ]; then
  echo "No compatible foundation update found."
  exit 0
fi

verified_version=""
while IFS= read -r candidate_version; do
  [ -n "$candidate_version" ] || continue
  : > "$verify_output"
  : > "$verify_log"
  if bash "$SCRIPT_DIR/verify_foundation_release.sh" \
    "$FOUNDATION_RELEASE_SOURCE_REFERENCE" \
    "$candidate_version" \
    "$verify_output" \
    "$FOUNDATION_RELEASE_SOURCE_PROVIDER" \
    "$FOUNDATION_RELEASE_SOURCE_API_BASE" \
    "${FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER:-}" >"$verify_log" 2>&1; then
    verified_version="$candidate_version"
    break
  fi
  cat "$verify_log" >&2
done < <(sed -n '/^candidates<<EOF$/,/^EOF$/p' "$latest_output" | sed '1d;$d')

if [ -z "$verified_version" ]; then
  echo "No compatible foundation release passed provenance verification." >&2
  exit 1
fi

commit_sha="$(grep '^commit_sha=' "$verify_output" | cut -d= -f2-)"
if [ -z "$commit_sha" ]; then
  echo "Verified foundation release did not return a commit SHA." >&2
  exit 1
fi

git init "$foundation_dir" >/dev/null
git -C "$foundation_dir" remote add origin "$(wp_plugin_base_provider_reference_git_url "$FOUNDATION_RELEASE_SOURCE_PROVIDER" "$FOUNDATION_RELEASE_SOURCE_API_BASE" "$FOUNDATION_RELEASE_SOURCE_REFERENCE")"
git -C "$foundation_dir" fetch --depth 1 origin "$commit_sha" >/dev/null
git -C "$foundation_dir" checkout --detach FETCH_HEAD >/dev/null

rm -rf "$ROOT_DIR/.wp-plugin-base"
mkdir -p "$ROOT_DIR/.wp-plugin-base"
rsync -a --exclude '.git' "$foundation_dir/" "$ROOT_DIR/.wp-plugin-base/"

perl -0pi -e "s/^FOUNDATION_VERSION=.*/FOUNDATION_VERSION=${verified_version}/m" "$(wp_plugin_base_config_path "$ROOT_DIR" "$CONFIG_OVERRIDE")"

bash "$ROOT_DIR/.wp-plugin-base/scripts/update/sync_child_repo.sh" "$CONFIG_OVERRIDE"
bash "$ROOT_DIR/.wp-plugin-base/scripts/ci/validate_project.sh" "$CONFIG_OVERRIDE"

case "$AUTOMATION_PROVIDER" in
  github)
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    ;;
  gitlab)
    git config user.name "gitlab-ci[bot]"
    git config user.email "gitlab-ci@example.invalid"
    ;;
esac

cat > "$body_file" <<EOF
This $(wp_plugin_base_provider_change_request_label "$AUTOMATION_PROVIDER") updates the vendored foundation and regenerates the managed workflow and documentation files.

Updated foundation version:
- \`${FOUNDATION_VERSION}\` -> \`${verified_version}\`

Security checks performed before proposing this update:
- release is published and supported by the configured foundation source provider
- tag matches the foundation semver contract
- signed release metadata matches the authoritative source, version, and commit
- tag commit is reachable from the foundation \`main\`
- release was produced by the protected foundation release flow
- release author is in the allowed release-author list
- vendored code is refreshed from the verified commit SHA
EOF

managed_paths="$(
  {
    printf '%s\n' ".wp-plugin-base"
    printf '%s\n' "$CONFIG_OVERRIDE"
    bash "$ROOT_DIR/.wp-plugin-base/scripts/ci/list_managed_files.sh" --mode stage "$CONFIG_OVERRIDE"
  } | awk '!seen[$0]++' | paste -sd, -
)"
export GIT_ADD_PATHS="$managed_paths"

bash "$SCRIPT_DIR/create_or_update_change_request.sh" \
  "chore/update-wp-plugin-base-${verified_version}" \
  "$BASE_BRANCH" \
  "chore: update wp-plugin-base to ${verified_version}" \
  "chore: update wp-plugin-base to ${verified_version}" \
  "$body_file"
