#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/provider.sh
. "$SCRIPT_DIR/../lib/provider.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "change-request title release note generation" jq

VERSION="${1:-}"
CONFIG_OVERRIDE="${2:-}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z [config-path]" >&2
  exit 1
fi

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

repository=""
case "$AUTOMATION_PROVIDER" in
  github)
    repository="${GITHUB_REPOSITORY:-}"
    if [ -z "$repository" ]; then
      repository="$(derive_repository github || true)"
    fi
    if [ -z "$repository" ]; then
      echo "Unable to resolve GitHub repository for CHANGELOG_SOURCE=change_request_titles." >&2
      exit 1
    fi
    wp_plugin_base_require_commands "GitHub change-request title release note generation" gh jq
    ;;
  gitlab)
    repository="${CI_PROJECT_PATH:-${AUTOMATION_PROJECT_PATH:-}}"
    if [ -z "$repository" ]; then
      repository="$(derive_repository gitlab || true)"
    fi
    if [ -z "$repository" ]; then
      echo "Unable to resolve GitLab project path for CHANGELOG_SOURCE=change_request_titles." >&2
      exit 1
    fi
    wp_plugin_base_require_commands "GitLab change-request title release note generation" curl jq
    ;;
  *)
    echo "Unsupported AUTOMATION_PROVIDER: $AUTOMATION_PROVIDER" >&2
    exit 1
    ;;
esac

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

case "$AUTOMATION_PROVIDER" in
  github)
    gh api --paginate \
      "repos/${repository}/pulls?state=closed&base=main&sort=updated&direction=desc&per_page=100" \
      | jq -s 'add' > "$prs_json_file"
    ;;
  gitlab)
    gitlab_token="${GITLAB_TOKEN:-${CI_JOB_TOKEN:-}}"
    if [ -z "$gitlab_token" ]; then
      echo "GITLAB_TOKEN or CI_JOB_TOKEN is required for CHANGELOG_SOURCE=change_request_titles." >&2
      exit 1
    fi
    gitlab_auth_header_name="PRIVATE-TOKEN"
    if [ -z "${GITLAB_TOKEN:-}" ] && [ -n "${CI_JOB_TOKEN:-}" ]; then
      gitlab_auth_header_name="JOB-TOKEN"
    fi
    gitlab_project_id="$(wp_plugin_base_provider_gitlab_project_id "$repository")"
    page=1
    printf '[]' > "$prs_json_file"
    while :; do
      page_json="$(
        curl -fsSL \
          --connect-timeout 10 \
          --max-time 60 \
          --header "${gitlab_auth_header_name}: ${gitlab_token}" \
          "${AUTOMATION_API_BASE}/projects/${gitlab_project_id}/merge_requests?state=merged&target_branch=main&scope=all&order_by=updated_at&sort=desc&per_page=100&page=${page}"
      )"
      jq -s '.[0] + .[1]' "$prs_json_file" <(printf '%s' "$page_json") > "${prs_json_file}.next"
      mv "${prs_json_file}.next" "$prs_json_file"
      page_count="$(printf '%s' "$page_json" | jq 'length')"
      if [ "$page_count" -lt 100 ]; then
        break
      fi
      page=$((page + 1))
    done
    ;;
esac

normalize_title() {
  local title="$1"
  title="$(printf '%s' "$title" | sed -E 's/[[:space:]]*\(#[0-9]+\)$//; s/[[:space:]]+$//; s/^[[:space:]]+//')"
  printf '%s' "$title"
}

extract_changelog_body_entries() {
  local raw_body="$1"
  local in_section=false
  local line heading item lower_item

  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*#{1,6}[[:space:]]+(.+)$ ]]; then
      heading="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]]+$//; s/^[[:space:]]+//')"
      if [[ "$heading" =~ ^(changelog|changes|release[[:space:]]+notes)([[:space:]]*[:.-].*)?$ ]]; then
        in_section=true
      elif [ "$in_section" = true ]; then
        in_section=false
      fi
      continue
    fi

    [ "$in_section" = true ] || continue

    item=""
    if [[ "$line" =~ ^[[:space:]]*[-*+][[:space:]]+\[[xX]\][[:space:]]+(.+)$ ]]; then
      item="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]*[-*+][[:space:]]+\[[[:space:]]\][[:space:]]+(.+)$ ]]; then
      continue
    elif [[ "$line" =~ ^[[:space:]]*[-*+][[:space:]]+(.+)$ ]]; then
      item="${BASH_REMATCH[1]}"
    else
      continue
    fi

    item="$(printf '%s' "$item" | sed -E 's/[[:space:]]+$//; s/^[[:space:]]+//')"
    lower_item="$(printf '%s' "$item" | tr '[:upper:]' '[:lower:]')"
    if [ -z "$item" ] || [ "$lower_item" = "none" ] || [ "$lower_item" = "_none_" ] || [ "$lower_item" = "n/a" ] || [ "$lower_item" = "na" ]; then
      continue
    fi

    printf '%s\n' "$item"
  done <<< "$raw_body"
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

  if [ "$AUTOMATION_PROVIDER" = "github" ]; then
    labels_csv="$(printf '%s' "$pr_json" | jq -r '[.labels[]?.name | ascii_downcase] | join(",")')"
  else
    labels_csv="$(printf '%s' "$pr_json" | jq -r '[.labels[]? | ascii_downcase] | join(",")')"
  fi
  if grep -Eqi '(^|,)(dependencies|automation|skip-changelog)(,|$)' <<<"$labels_csv"; then
    continue
  fi

  raw_body="$(printf '%s' "$pr_json" | jq -r '.body // .description // empty')"
  body_entries="$(extract_changelog_body_entries "$raw_body")"
  if [ -n "$body_entries" ]; then
    while IFS= read -r body_entry; do
      [ -n "$body_entry" ] || continue
      category="$(detect_category "$body_entry" "$labels_csv")"
      append_entry "$category" "$body_entry"
      entries=$((entries + 1))
    done <<< "$body_entries"
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
