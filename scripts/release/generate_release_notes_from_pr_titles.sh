#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "PR-title release note generation" gh jq

VERSION="${1:-}"
CONFIG_OVERRIDE="${2:-}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z [config-path]" >&2
  exit 1
fi

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

derive_repository() {
  local remote_url
  remote_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
  if [ -z "$remote_url" ]; then
    return 1
  fi

  remote_url="${remote_url%.git}"
  case "$remote_url" in
    git@github.com:*)
      printf '%s\n' "${remote_url#git@github.com:}"
      ;;
    https://github.com/*)
      printf '%s\n' "${remote_url#https://github.com/}"
      ;;
    ssh://git@github.com/*)
      printf '%s\n' "${remote_url#ssh://git@github.com/}"
      ;;
    *)
      return 1
      ;;
  esac
}

repository="${GITHUB_REPOSITORY:-}"
if [ -z "$repository" ]; then
  repository="$(derive_repository || true)"
fi
if [ -z "$repository" ]; then
  echo "Unable to resolve GitHub repository for CHANGELOG_SOURCE=prs_titles." >&2
  exit 1
fi

previous_tag="$(
  git -C "$ROOT_DIR" tag --sort=-v:refname \
    | awk '/^[0-9]+\.[0-9]+\.[0-9]+$/ { print; exit }'
)"

commit_range="HEAD"
if [ -n "$previous_tag" ]; then
  commit_range="${previous_tag}..HEAD"
fi

commit_shas_file="$(mktemp)"
prs_json_file="$(mktemp)"
add_file="$(mktemp)"
fix_file="$(mktemp)"
tweak_file="$(mktemp)"
update_file="$(mktemp)"
dev_file="$(mktemp)"

cleanup() {
  rm -f "$commit_shas_file" "$prs_json_file" "$add_file" "$fix_file" "$tweak_file" "$update_file" "$dev_file"
}
trap cleanup EXIT

git -C "$ROOT_DIR" rev-list "$commit_range" > "$commit_shas_file"

gh api --paginate \
  "repos/${repository}/pulls?state=closed&base=main&sort=updated&direction=desc&per_page=100" \
  | jq -s 'add' > "$prs_json_file"

normalize_title() {
  local title="$1"
  title="$(printf '%s' "$title" | sed -E 's/[[:space:]]*\(#[0-9]+\)$//; s/[[:space:]]+$//; s/^[[:space:]]+//')"
  printf '%s' "$title"
}

entry_with_period() {
  local text="$1"
  if [[ "$text" =~ [.!?]$ ]]; then
    printf '%s' "$text"
  else
    printf '%s.' "$text"
  fi
}

detect_category() {
  local title="$1"
  local labels="$2"

  if [[ "$title" =~ ^[[:space:]]*(Add|ADD)[[:space:]:-] ]]; then
    printf '%s\n' "Add"
    return
  fi
  if [[ "$title" =~ ^[[:space:]]*(Fix|FIX)[[:space:]:-] ]]; then
    printf '%s\n' "Fix"
    return
  fi
  if [[ "$title" =~ ^[[:space:]]*(Tweak|TWEAK)[[:space:]:-] ]]; then
    printf '%s\n' "Tweak"
    return
  fi
  if [[ "$title" =~ ^[[:space:]]*(Update|UPDATE)[[:space:]:-] ]]; then
    printf '%s\n' "Update"
    return
  fi
  if [[ "$title" =~ ^[[:space:]]*(Dev|DEV)[[:space:]:-] ]]; then
    printf '%s\n' "Dev"
    return
  fi

  if grep -Eqi '(^|,)(bug|fix|bugfix)(,|$)' <<<"$labels"; then
    printf '%s\n' "Fix"
    return
  fi
  if grep -Eqi '(^|,)(enhancement|feature)(,|$)' <<<"$labels"; then
    printf '%s\n' "Add"
    return
  fi
  if grep -Eqi '(^|,)(performance|perf)(,|$)' <<<"$labels"; then
    printf '%s\n' "Tweak"
    return
  fi
  if grep -Eqi '(^|,)(docs|documentation)(,|$)' <<<"$labels"; then
    printf '%s\n' "Dev"
    return
  fi

  printf '%s\n' "Update"
}

append_entry() {
  local category="$1"
  local title="$2"
  local line
  line="* ${category} - $(entry_with_period "$title")"

  case "$category" in
    Add) printf '%s\n' "$line" >> "$add_file" ;;
    Fix) printf '%s\n' "$line" >> "$fix_file" ;;
    Tweak) printf '%s\n' "$line" >> "$tweak_file" ;;
    Update) printf '%s\n' "$line" >> "$update_file" ;;
    Dev) printf '%s\n' "$line" >> "$dev_file" ;;
  esac
}

entries=0
while IFS= read -r pr_json; do
  [ -n "$pr_json" ] || continue
  merged_sha="$(printf '%s' "$pr_json" | jq -r '.merge_commit_sha // empty')"
  [ -n "$merged_sha" ] || continue
  if ! grep -Fxq "$merged_sha" "$commit_shas_file"; then
    continue
  fi

  labels_csv="$(printf '%s' "$pr_json" | jq -r '[.labels[]?.name | ascii_downcase] | join(",")')"
  if grep -Eqi '(^|,)(dependencies|automation|skip-changelog)(,|$)' <<<"$labels_csv"; then
    continue
  fi

  raw_title="$(printf '%s' "$pr_json" | jq -r '.title // empty')"
  [ -n "$raw_title" ] || continue
  title="$(normalize_title "$raw_title")"
  category="$(detect_category "$title" "$labels_csv")"
  append_entry "$category" "$title"
  entries=$((entries + 1))
done < <(jq -c '.[] | select(.merged_at != null and .merge_commit_sha != null)' "$prs_json_file")

if [ "$entries" -eq 0 ]; then
  echo "* Update - Maintenance release."
  exit 0
fi

for bucket in "$add_file" "$fix_file" "$tweak_file" "$update_file" "$dev_file"; do
  if [ -s "$bucket" ]; then
    cat "$bucket"
  fi
done
