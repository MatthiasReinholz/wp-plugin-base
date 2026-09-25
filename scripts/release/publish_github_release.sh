#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "GitHub release publication" gh jq cmp

REPAIR_MODE='false'
MARK_LATEST='false'
PRERELEASE='false'
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repair)
      REPAIR_MODE='true'
      shift
      ;;
    --mark-latest)
      MARK_LATEST='true'
      shift
      ;;
    --prerelease)
      PRERELEASE='true'
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--repair] [--mark-latest|--prerelease] tag-name release-title notes-file [asset ...]" >&2
      exit 0
      ;;
    --*)
      echo "Unsupported option: $1" >&2
      echo "Usage: $0 [--repair] [--mark-latest|--prerelease] tag-name release-title notes-file [asset ...]" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

TAG_NAME="${1:-}"
RELEASE_TITLE="${2:-}"
NOTES_FILE="${3:-}"
shift 3 || true

if [ -z "$TAG_NAME" ] || [ -z "$RELEASE_TITLE" ] || [ -z "$NOTES_FILE" ]; then
  echo "Usage: $0 [--repair] [--mark-latest|--prerelease] tag-name release-title notes-file [asset ...]" >&2
  exit 1
fi

if [ ! -f "$NOTES_FILE" ]; then
  echo "Release notes file not found: $NOTES_FILE" >&2
  exit 1
fi

if [ "$PRERELEASE" = 'true' ] && [[ ! "$TAG_NAME" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+-[0-9A-Za-z][0-9A-Za-z.-]*$ ]]; then
  echo "Prerelease publication requires a prerelease version tag: $TAG_NAME" >&2
  exit 1
fi

latest_flag='--latest=false'
if [ "$MARK_LATEST" = 'true' ]; then
  if [ "$PRERELEASE" = 'true' ]; then
    echo 'Prereleases cannot be marked latest.' >&2
    exit 1
  fi
  if [[ ! "$TAG_NAME" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Only stable semantic versions may be marked latest: $TAG_NAME" >&2
    exit 1
  fi
  # Inspect every published release, not creation order or a limited page. A
  # historical repair remains possible, but can never promote an older version.
  published_tags="$(gh api --paginate "repos/${GITHUB_REPOSITORY}/releases?per_page=100" \
    --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name')"
  newer_tags="$(printf '%s\n' "$published_tags" | jq -Rsr --arg candidate "${TAG_NAME#v}" '
    ($candidate | split(".") | map(tonumber)) as $candidate_version
    | split("\n")[]
    | select(test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$"))
    | select((ltrimstr("v") | split(".") | map(tonumber)) > $candidate_version)
  ')"
  if [ -z "$newer_tags" ]; then
    latest_flag='--latest'
  else
    echo "Keeping newer published release(s) latest while repairing $TAG_NAME: $newer_tags"
  fi
fi

if gh release view "$TAG_NAME" --repo "${GITHUB_REPOSITORY}" >/dev/null 2>&1; then
  if [ "$REPAIR_MODE" != 'true' ]; then
    echo "Release ${TAG_NAME} already exists. Re-run with --repair to update an existing release." >&2
    exit 1
  fi

  # Plugin ZIPs and actionable foundation metadata are immutable, even during
  # explicit evidence repair. Different payload bytes require a new version.
  for asset_path in "$@"; do
    case "$asset_path" in
      *.zip|*/dist-foundation-release.json|dist-foundation-release.json)
        asset_name="$(basename "$asset_path")"
        existing_assets="$(gh release view "$TAG_NAME" --repo "$GITHUB_REPOSITORY" --json assets)"
        if [ "$(printf '%s' "$existing_assets" | jq --arg name "$asset_name" '[.assets[] | select(.name == $name)] | length')" -gt 0 ]; then
          download_dir="$(mktemp -d)"
          trap 'rm -rf "$download_dir"' EXIT
          gh release download "$TAG_NAME" --repo "$GITHUB_REPOSITORY" --dir "$download_dir" --pattern "$asset_name"
          if ! cmp -s "$asset_path" "$download_dir/$asset_name"; then
            echo "Published payload $asset_name differs from the rebuilt payload; create a new version instead of replacing it." >&2
            exit 1
          fi
          rm -rf "$download_dir"
          trap - EXIT
        fi
        ;;
    esac
  done

  if [ "$#" -gt 0 ]; then
    gh release upload "$TAG_NAME" "$@" --repo "${GITHUB_REPOSITORY}" --clobber
  fi

  # Omitting the latest flag on repair preserves the current designation.
  # --latest=false could demote the current latest release during evidence repair.
  edit_args=(--repo "$GITHUB_REPOSITORY" --title "$RELEASE_TITLE" \
    --notes-file "$NOTES_FILE" --draft=false "--prerelease=$PRERELEASE")
  if [ "$PRERELEASE" = 'true' ]; then
    edit_args+=(--latest=false)
  elif [ "$latest_flag" = '--latest' ]; then
    edit_args+=(--latest)
  fi
  gh release edit "$TAG_NAME" "${edit_args[@]}"

  exit 0
fi

create_args=(--repo "$GITHUB_REPOSITORY" --verify-tag --title "$RELEASE_TITLE" \
  "$latest_flag" --notes-file "$NOTES_FILE")
if [ "$PRERELEASE" = 'true' ]; then create_args+=(--prerelease); fi
gh release create "$TAG_NAME" "$@" "${create_args[@]}"
