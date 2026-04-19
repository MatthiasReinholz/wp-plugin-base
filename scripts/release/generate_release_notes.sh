#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

VERSION="${1:-}"
CONFIG_OVERRIDE="${2:-}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z [config-path]" >&2
  exit 1
fi

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

if [ "${CHANGELOG_SOURCE:-commits}" = "change_request_titles" ] || [ "${CHANGELOG_SOURCE:-commits}" = "prs_titles" ]; then
  exec bash "$SCRIPT_DIR/generate_release_notes_from_pr_titles.sh" "$VERSION" "$CONFIG_OVERRIDE"
fi

previous_tag="$(
  git tag --sort=-v:refname \
    | awk '/^[0-9]+\.[0-9]+\.[0-9]+$/ { print; exit }'
)"

if [ -n "$previous_tag" ]; then
  notes="$(
    git log --no-merges --format='%s' "${previous_tag}..HEAD" \
      | awk '
        function classify(subject, lower) {
          if (subject ~ /^[[:space:]]*[Aa]dd([[:space:]:-]|$)/) return "Add"
          if (subject ~ /^[[:space:]]*[Ff]ix([[:space:]:-]|$)/) return "Fix"
          if (subject ~ /^[[:space:]]*[Tt]weak([[:space:]:-]|$)/) return "Tweak"
          if (subject ~ /^[[:space:]]*[Uu]pdate([[:space:]:-]|$)/) return "Update"
          if (subject ~ /^[[:space:]]*[Dd]ev([[:space:]:-]|$)/) return "Dev"

          lower = tolower(subject)
          if (lower ~ /bug|fix|hotfix|regression|patch/) return "Fix"
          if (lower ~ /feature|feat|add|introduce|support/) return "Add"
          if (lower ~ /perf|performance|optimi[sz]e|speed|tweak/) return "Tweak"
          if (lower ~ /docs|documentation|readme|changelog/) return "Dev"
          return "Update"
        }
        {
          subject = $0
          gsub(/[[:space:]]+$/, "", subject)
          if (subject == "") next
          if (subject !~ /[.!?]$/) subject = subject "."
          printf "* %s - %s\n", classify(subject), subject
        }
      '
  )"
else
  notes="$(
    git log --no-merges --format='%s' \
      | awk '
        function classify(subject, lower) {
          if (subject ~ /^[[:space:]]*[Aa]dd([[:space:]:-]|$)/) return "Add"
          if (subject ~ /^[[:space:]]*[Ff]ix([[:space:]:-]|$)/) return "Fix"
          if (subject ~ /^[[:space:]]*[Tt]weak([[:space:]:-]|$)/) return "Tweak"
          if (subject ~ /^[[:space:]]*[Uu]pdate([[:space:]:-]|$)/) return "Update"
          if (subject ~ /^[[:space:]]*[Dd]ev([[:space:]:-]|$)/) return "Dev"

          lower = tolower(subject)
          if (lower ~ /bug|fix|hotfix|regression|patch/) return "Fix"
          if (lower ~ /feature|feat|add|introduce|support/) return "Add"
          if (lower ~ /perf|performance|optimi[sz]e|speed|tweak/) return "Tweak"
          if (lower ~ /docs|documentation|readme|changelog/) return "Dev"
          return "Update"
        }
        {
          subject = $0
          gsub(/[[:space:]]+$/, "", subject)
          if (subject == "") next
          if (subject !~ /[.!?]$/) subject = subject "."
          printf "* %s - %s\n", classify(subject), subject
        }
      '
  )"
fi

if [ -z "$notes" ]; then
  notes="* Update - Maintenance release."
fi

printf '%s\n' "$notes"
