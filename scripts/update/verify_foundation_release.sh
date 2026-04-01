#!/usr/bin/env bash

set -euo pipefail

REPOSITORY="${1:-}"
VERSION="${2:-}"
FOUNDATION_DIR="${3:-}"

if [ -z "$REPOSITORY" ] || [ -z "$VERSION" ] || [ -z "$FOUNDATION_DIR" ]; then
  echo "Usage: $0 repository version foundation-dir" >&2
  exit 1
fi

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  echo "GH_TOKEN or GITHUB_TOKEN is required." >&2
  exit 1
fi

allowed_authors="${FOUNDATION_ALLOWED_RELEASE_AUTHORS:-github-actions[bot]}"

api() {
  local path="$1"
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com${path}"
}

release_json="$(api "/repos/${REPOSITORY}/releases/tags/${VERSION}")"

if [ "$(printf '%s' "$release_json" | jq -r '.draft')" != "false" ]; then
  echo "Foundation release ${VERSION} is still a draft." >&2
  exit 1
fi

if [ "$(printf '%s' "$release_json" | jq -r '.prerelease')" != "false" ]; then
  echo "Foundation release ${VERSION} is a prerelease." >&2
  exit 1
fi

release_author="$(printf '%s' "$release_json" | jq -r '.author.login // empty')"
author_allowed=false
while IFS= read -r author; do
  if [ "$author" = "$release_author" ]; then
    author_allowed=true
    break
  fi
done < <(printf '%s\n' "$allowed_authors" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [ "$author_allowed" != true ]; then
  echo "Foundation release ${VERSION} was authored by ${release_author}, which is not in the allowlist." >&2
  exit 1
fi

tag_ref_json="$(api "/repos/${REPOSITORY}/git/ref/tags/${VERSION}")"
tag_object_type="$(printf '%s' "$tag_ref_json" | jq -r '.object.type')"
tag_object_sha="$(printf '%s' "$tag_ref_json" | jq -r '.object.sha')"

if [ "$tag_object_type" = "tag" ]; then
  tag_object_json="$(api "/repos/${REPOSITORY}/git/tags/${tag_object_sha}")"
  commit_sha="$(printf '%s' "$tag_object_json" | jq -r '.object.sha')"
else
  commit_sha="$tag_object_sha"
fi

git -C "$FOUNDATION_DIR" fetch --depth 1 origin main >/dev/null 2>&1
if ! git -C "$FOUNDATION_DIR" merge-base --is-ancestor "$commit_sha" FETCH_HEAD; then
  echo "Foundation release ${VERSION} does not point to a commit on origin/main." >&2
  exit 1
fi

pulls_json="$(
  curl -fsSL \
    -H "Accept: application/vnd.github.groot-preview+json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPOSITORY}/commits/${commit_sha}/pulls"
)"

matching_count="$(printf '%s' "$pulls_json" | jq -r --arg sha "$commit_sha" '
  map(
    select(
      .merged_at != null and
      .base.ref == "main" and
      (.head.ref | test("^(release|hotfix)/v[0-9]+\\.[0-9]+\\.[0-9]+$")) and
      .merge_commit_sha == $sha
    )
  ) | length
')"

if [ "$matching_count" -eq 0 ]; then
  echo "Foundation release ${VERSION} was not produced by a merged release/hotfix PR on main." >&2
  exit 1
fi

echo "Verified provenance for ${REPOSITORY} ${VERSION} (${commit_sha})"
