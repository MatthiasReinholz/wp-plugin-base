#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

RELEASE_TYPE="${1:-}"
VERSION_OVERRIDE="${2:-}"
BASE_REF="${3:-main}"
CONFIG_OVERRIDE="${4:-${WP_PLUGIN_BASE_CONFIG:-.wp-plugin-base.env}}"

if [ -z "$RELEASE_TYPE" ]; then
  echo "Usage: $0 <patch|minor|major|custom> [version] [base-ref] [config-path]" >&2
  exit 1
fi

wp_plugin_base_require_commands "release change-request preparation" git perl

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

derive_repository() {
  local provider="$1"
  local remote_url
  remote_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
  if [ -z "$remote_url" ]; then
    return 1
  fi

  wp_plugin_base_provider_infer_reference_from_remote "$provider" "$remote_url"
}

AUTOMATION_PROVIDER="${AUTOMATION_PROVIDER:-github}"
AUTOMATION_API_BASE="${AUTOMATION_API_BASE:-$(wp_plugin_base_provider_default_api_base "$AUTOMATION_PROVIDER")}"

case "$AUTOMATION_PROVIDER" in
  github)
    repository="${GITHUB_REPOSITORY:-}"
    if [ -z "$repository" ]; then
      repository="$(derive_repository github || true)"
    fi
    ;;
  gitlab)
    repository="${CI_PROJECT_PATH:-${AUTOMATION_PROJECT_PATH:-}}"
    if [ -z "$repository" ]; then
      repository="$(derive_repository gitlab || true)"
    fi
    ;;
  *)
    echo "Unsupported AUTOMATION_PROVIDER: $AUTOMATION_PROVIDER" >&2
    exit 1
    ;;
esac

if [ -z "$repository" ]; then
  echo "Unable to resolve repository for prepare-release automation." >&2
  exit 1
fi

repository_owner="${repository%%/*}"

if [ "$RELEASE_TYPE" = "custom" ]; then
  if [[ ! "$VERSION_OVERRIDE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Custom version must use x.y.z format." >&2
    exit 1
  fi
  version="$VERSION_OVERRIDE"
else
  version="$(bash "$SCRIPT_DIR/next_version.sh" "$RELEASE_TYPE" "$CONFIG_OVERRIDE")"
fi

release_branch="release/${version}"
source_output="$(mktemp)"
body_file="$(mktemp)"

cleanup() {
  rm -f "$source_output" "$body_file"
}
trap cleanup EXIT

bash "$SCRIPT_DIR/../update/resolve_release_branch_source.sh" \
  "$repository" \
  "$repository_owner" \
  "$release_branch" \
  "$BASE_REF" \
  "$source_output"

source_ref="$(grep '^ref=' "$source_output" | cut -d= -f2-)"

git fetch origin "$source_ref"
git checkout --detach FETCH_HEAD

bash "$SCRIPT_DIR/bump_version.sh" "$version" "$CONFIG_OVERRIDE"
bash "$SCRIPT_DIR/generate_pot.sh" "$CONFIG_OVERRIDE"

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

change_request_label="$(wp_plugin_base_provider_change_request_label "$AUTOMATION_PROVIDER")"
after_merge_instructions='- the release tag `'${version}'` becomes the publication target
- the platform release job publishes the install ZIP plus release evidence'

if [ "$AUTOMATION_PROVIDER" = "gitlab" ]; then
  after_merge_instructions='- create and push the release tag manually after merge:
  ```bash
  git tag '"${version}"'
  git push origin '"${version}"'
  ```
- the GitLab tag pipeline publishes the install ZIP plus release evidence'
fi

cat > "$body_file" <<EOF
This ${change_request_label} was created by the managed release preparation flow.

Included changes:
- bump plugin metadata to \`${version}\`
- add auto-generated changelog notes for \`${version}\`
- update the release metadata based on the project config
- derive the version using release type \`${RELEASE_TYPE}\`

Automated checks on this ${change_request_label}:
- version metadata consistency
- release branch name matches the version bump
- release changelog section exists
- release changelog entry contains bullet items
- workflow and automation audit checks
- PHP and JavaScript syntax
- package build

## Editing the changelog

Before merging:
1. Review entries under \`= ${version} =\`
2. Edit entries directly on the release branch to reword or reorder
3. Keep each entry as a \`* \` bullet with an \`Add/Fix/Tweak/Update/Dev\` prefix

After merge:
${after_merge_instructions}
EOF

changed_paths="$(git status --porcelain | awk '{print $2}' | paste -sd, -)"
if [ -n "$changed_paths" ]; then
  export GIT_ADD_PATHS="$changed_paths"
fi

bash "$SCRIPT_DIR/../update/create_or_update_change_request.sh" \
  "$release_branch" \
  "$BASE_REF" \
  "Release ${version}" \
  "Release ${version}" \
  "$body_file"
