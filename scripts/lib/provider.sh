#!/usr/bin/env bash

set -euo pipefail

wp_plugin_base_url_host() {
  local url="${1:-}"
  local https_scheme="https:"
  local https_prefix="${https_scheme}//"
  local remainder=""
  local host=""

  if [ -z "$url" ] || [[ "$url" != "${https_prefix}"* ]]; then
    printf '%s\n' ""
    return
  fi

  remainder="${url#"$https_prefix"}"
  host="${remainder%%/*}"
  host="${host#*@}"
  if [[ "$host" = \[*\]* ]]; then
    host="${host#\[}"
    host="${host%%\]*}"
    printf '%s\n' "$host"
    return
  fi
  host="${host%%:*}"
  printf '%s\n' "$host"
}

wp_plugin_base_host_is_default_trusted_git_host() {
  case "${1:-}" in
    github.com|api.github.com|gitlab.com|token.actions.githubusercontent.com)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

wp_plugin_base_host_is_local_or_private() {
  local host="${1:-}"
  local lower_host=""
  local second_octet=""
  local components=()
  local component=""

  lower_host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  lower_host="${lower_host%.}"
  if [[ "$lower_host" = \[*\] ]]; then
    lower_host="${lower_host#\[}"
    lower_host="${lower_host%\]}"
  fi

  case "$lower_host" in
    ""|localhost|localhost.localdomain|*.localhost|*.local|*.internal)
      return 0
      ;;
  esac

  if [[ "$lower_host" != *.* && "$lower_host" != *:* ]]; then
    return 0
  fi

  case "$lower_host" in
    ::|::1|0:0:0:0:0:0:0:1|fe[89ab]:*|fc*:*|fd*:*)
      return 0
      ;;
  esac

  if [[ "$lower_host" =~ ^::ffff:(127|10|0)\. ]]; then
    return 0
  fi

  if [[ "$lower_host" =~ ^::ffff:192\.168\. ]]; then
    return 0
  fi

  if [[ "$lower_host" =~ ^::ffff:169\.254\. ]]; then
    return 0
  fi

  if [[ "$lower_host" =~ ^::ffff:172\.([0-9]{1,3})\. ]]; then
    if [ "${BASH_REMATCH[1]}" -ge 16 ] && [ "${BASH_REMATCH[1]}" -le 31 ]; then
      return 0
    fi
  fi

  if [[ "$lower_host" =~ ^::ffff:100\.([0-9]{1,3})\. ]]; then
    if [ "${BASH_REMATCH[1]}" -ge 64 ] && [ "${BASH_REMATCH[1]}" -le 127 ]; then
      return 0
    fi
  fi

  if [[ "$lower_host" =~ ^::ffff:198\.(18|19)\. ]]; then
    return 0
  fi

  if [[ "$lower_host" =~ ^([0-9]+|0x[0-9a-f]+)(\.([0-9]+|0x[0-9a-f]+))*$ ]] && [[ ! "$lower_host" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    return 0
  fi

  if [[ "$lower_host" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    IFS='.' read -r -a components <<< "$lower_host"
    for component in "${components[@]}"; do
      if [ "$component" -gt 255 ]; then
        return 0
      fi
      if [[ "$component" =~ ^0[0-9]+$ ]]; then
        return 0
      fi
    done
  fi

  if [[ "$lower_host" =~ ^0\. ]]; then
    return 0
  fi

  if [[ "$lower_host" =~ ^127\. ]]; then
    return 0
  fi

  if [[ "$lower_host" =~ ^10\. ]]; then
    return 0
  fi

  if [[ "$lower_host" =~ ^192\.168\. ]]; then
    return 0
  fi

  if [[ "$lower_host" =~ ^169\.254\. ]]; then
    return 0
  fi

  if [[ "$lower_host" =~ ^100\.([0-9]{1,3})\. ]]; then
    second_octet="${BASH_REMATCH[1]}"
    if [ "$second_octet" -ge 64 ] && [ "$second_octet" -le 127 ]; then
      return 0
    fi
  fi

  if [[ "$lower_host" =~ ^172\.([0-9]{1,3})\. ]]; then
    if [ "${BASH_REMATCH[1]}" -ge 16 ] && [ "${BASH_REMATCH[1]}" -le 31 ]; then
      return 0
    fi
  fi

  if [[ "$lower_host" =~ ^198\.(18|19)\. ]]; then
    return 0
  fi

  return 1
}

wp_plugin_base_provider_default_api_base() {
  local provider="${1:-}"

  case "$provider" in
    github|github-release)
      printf '%s\n' "https://api.github.com"
      ;;
    gitlab|gitlab-release)
      printf '%s\n' "https://gitlab.com/api/v4"
      ;;
    *)
      printf '%s\n' ""
      ;;
  esac
}

wp_plugin_base_provider_gitlab_project_id() {
  local reference="${1:-}"

  jq -rn --arg value "$reference" '$value | @uri'
}

wp_plugin_base_provider_gitlab_web_base() {
  local api_base="${1:-}"

  api_base="${api_base%/}"
  printf '%s\n' "${api_base%/api/v4}"
}

wp_plugin_base_provider_github_web_base() {
  local api_base="${1:-}"

  api_base="${api_base%/}"
  case "$api_base" in
    https://api.github.com)
      printf '%s\n' "https://github.com"
      ;;
    */api/v3)
      printf '%s\n' "${api_base%/api/v3}"
      ;;
    *)
      printf '%s\n' "${api_base%/api}"
      ;;
  esac
}

wp_plugin_base_provider_web_base() {
  local provider="${1:-}"
  local api_base="${2:-}"

  case "$provider" in
    github|github-release)
      wp_plugin_base_provider_github_web_base "$api_base"
      ;;
    gitlab|gitlab-release)
      wp_plugin_base_provider_gitlab_web_base "$api_base"
      ;;
    *)
      printf '%s\n' ""
      ;;
  esac
}

wp_plugin_base_provider_reference_url() {
  local provider="${1:-}"
  local api_base="${2:-}"
  local reference="${3:-}"

  case "$provider" in
    github|github-release)
      printf '%s/%s\n' "$(wp_plugin_base_provider_github_web_base "$api_base")" "$reference"
      ;;
    gitlab|gitlab-release)
      printf '%s/%s\n' "$(wp_plugin_base_provider_gitlab_web_base "$api_base")" "$reference"
      ;;
    *)
      printf '%s\n' ""
      ;;
  esac
}

wp_plugin_base_provider_reference_git_url() {
  local provider="${1:-}"
  local api_base="${2:-}"
  local reference="${3:-}"
  local web_url=""

  web_url="$(wp_plugin_base_provider_reference_url "$provider" "$api_base" "$reference")"
  if [ -z "$web_url" ]; then
    printf '%s\n' ""
    return
  fi

  printf '%s.git\n' "$web_url"
}

wp_plugin_base_provider_sigstore_oidc_issuer() {
  local provider="${1:-}"
  local api_base="${2:-}"
  local host=""

  case "$provider" in
    github|github-release)
      printf '%s\n' "https://token.actions.githubusercontent.com"
      ;;
    gitlab|gitlab-release)
      host="$(wp_plugin_base_url_host "$api_base")"
      if [ "$host" = "gitlab.com" ]; then
        wp_plugin_base_provider_gitlab_web_base "$api_base"
        return
      fi
      printf '%s\n' ""
      ;;
    *)
      printf '%s\n' ""
      ;;
  esac
}

wp_plugin_base_escape_extended_regex_literal() {
  local value="${1:-}"
  local escaped=""
  local char=""
  local index=0

  for ((index = 0; index < ${#value}; index++)); do
    char="${value:index:1}"
    case "$char" in
      "\\"|"."|"["|"]"|"("|")"|"{"|"}"|"^"|"$"|"*"|"+"|"?"|"|")
        escaped+="\\$char"
        ;;
      *)
        escaped+="$char"
        ;;
    esac
  done

  printf '%s\n' "$escaped"
}

wp_plugin_base_provider_sigstore_identity_regex() {
  local provider="${1:-}"
  local api_base="${2:-}"
  local reference="${3:-}"
  local scope="${4:-plugin}"
  local web_base=""
  local escaped_web_base=""
  local escaped_reference=""

  web_base="$(wp_plugin_base_provider_web_base "$provider" "$api_base")"
  escaped_web_base="$(wp_plugin_base_escape_extended_regex_literal "$web_base")"
  escaped_reference="$(wp_plugin_base_escape_extended_regex_literal "$reference")"

  case "$provider" in
    github|github-release)
      case "$scope" in
        plugin)
          printf '^%s/%s/\\.github/workflows/(finalize-release|release)\\.yml@refs/heads/main$\n' "$escaped_web_base" "$escaped_reference"
          ;;
        foundation)
          printf '^%s/%s/\\.github/workflows/(finalize-foundation-release|release-foundation)\\.yml@refs/heads/main$\n' "$escaped_web_base" "$escaped_reference"
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    gitlab|gitlab-release)
      printf '^%s/%s/\\.gitlab-ci\\.yml@refs/heads/main$\n' "$escaped_web_base" "$escaped_reference"
      ;;
    *)
      return 1
      ;;
  esac
}

wp_plugin_base_provider_change_request_label() {
  case "${1:-}" in
    gitlab)
      printf '%s\n' "merge request"
      ;;
    *)
      printf '%s\n' "pull request"
      ;;
  esac
}

wp_plugin_base_provider_infer_reference_from_remote() {
  local provider="${1:-}"
  local remote_url="${2:-}"
  local trimmed_url=""
  local github_https_prefix="https://github.com/"
  local https_prefix="https://"

  remote_url="${remote_url%.git}"

  case "$provider" in
    github|github-release)
      case "$remote_url" in
        git@github.com:*)
          printf '%s\n' "${remote_url#git@github.com:}"
          return 0
          ;;
        "${github_https_prefix}"*)
          printf '%s\n' "${remote_url#"$github_https_prefix"}"
          return 0
          ;;
        ssh://git@github.com/*)
          printf '%s\n' "${remote_url#ssh://git@github.com/}"
          return 0
          ;;
      esac
      ;;
    gitlab|gitlab-release)
      case "$remote_url" in
        git@*:*)
          trimmed_url="${remote_url#git@}"
          trimmed_url="${trimmed_url#*:}"
          printf '%s\n' "$trimmed_url"
          return 0
          ;;
        ssh://git@*/*)
          trimmed_url="${remote_url#ssh://git@}"
          trimmed_url="${trimmed_url#*/}"
          printf '%s\n' "$trimmed_url"
          return 0
          ;;
        "${https_prefix}"*/*)
          trimmed_url="${remote_url#"$https_prefix"}"
          trimmed_url="${trimmed_url#*/}"
          printf '%s\n' "$trimmed_url"
          return 0
          ;;
      esac
      ;;
  esac

  return 1
}
