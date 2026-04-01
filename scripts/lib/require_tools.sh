#!/usr/bin/env bash

set -euo pipefail

wp_plugin_base_require_commands() {
  local context="$1"
  shift

  local missing=()
  local command

  for command in "$@"; do
    if ! command -v "$command" >/dev/null 2>&1; then
      missing+=("$command")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    return 0
  fi

  {
    printf 'Missing required command'
    if [ "${#missing[@]}" -gt 1 ]; then
      printf 's'
    fi
    printf ' for %s: %s\n' "$context" "${missing[*]}"

    for command in "${missing[@]}"; do
      case "$command" in
        gh)
          echo "- gh: required for GitHub release and pull request automation."
          ;;
        jq)
          echo "- jq: required for GitHub API response parsing."
          ;;
        node)
          echo "- node: required for JavaScript syntax validation."
          ;;
        perl)
          echo "- perl: required for template rendering and metadata rewriting."
          ;;
        php)
          echo "- php: required for PHP syntax validation."
          ;;
        rg)
          echo "- rg: required for workflow policy scans."
          ;;
        rsync)
          echo "- rsync: required for packaging and vendored foundation sync."
          ;;
        ruby)
          echo "- ruby: required for workflow YAML permission auditing."
          ;;
        svn)
          echo "- svn: required only for WordPress.org deployment."
          ;;
        unzip)
          echo "- unzip: optional for most flows, but required here for archive structure verification."
          ;;
        zip)
          echo "- zip: required for plugin package creation."
          ;;
      esac
    done
  } >&2

  exit 1
}
