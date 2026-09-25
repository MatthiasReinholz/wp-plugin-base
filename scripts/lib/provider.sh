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
  local release_tag="${5:-}"
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
      if [[ ! "$release_tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "GitLab Sigstore verification requires an exact stable release tag." >&2
        return 1
      fi
      printf '^%s/%s//\\.gitlab-ci\\.yml@refs/tags/%s$\n' "$escaped_web_base" "$escaped_reference" "$(wp_plugin_base_escape_extended_regex_literal "$release_tag")"
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

# curl reads headers from this mode-600 file; tokens never become process args.
# An empty file deliberately represents an unauthenticated public API request.
wp_plugin_base_provider_write_auth_header() {
  local provider="$1"
  local destination="$2"
  local token=''
  local header=''
  case "$provider" in
    github|github-release)
      token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
      header='Authorization: Bearer'
      ;;
    gitlab|gitlab-release)
      token="${GITLAB_TOKEN:-${CI_JOB_TOKEN:-}}"
      header='PRIVATE-TOKEN:'
      if [ -z "${GITLAB_TOKEN:-}" ]; then header='JOB-TOKEN:'; fi
      ;;
    *) echo "Unsupported authentication provider: $provider" >&2; return 1 ;;
  esac
  case "$token" in
    *$'\r'*|*$'\n'*) echo 'Provider token contains an invalid line break.' >&2; return 1 ;;
  esac
  (umask 077; : > "$destination"; chmod 600 "$destination"; if [ -n "$token" ]; then printf '%s %s\n' "$header" "$token" > "$destination"; fi)
}

# Uploaded web URLs have an authenticated API equivalent (GitLab >=17.4).
# Never send a project credential to a foreign asset origin or follow redirects.
wp_plugin_base_provider_gitlab_asset_api_url() {
  local api_base="$1"
  local reference="$2"
  local url="$3"
  local web_base=''
  web_base="$(wp_plugin_base_provider_gitlab_web_base "$api_base")"
  case "$url" in
    "$web_base/"*) ;;
    *) echo 'Refusing authenticated download from a foreign release asset origin.' >&2; return 1 ;;
  esac
  if [[ "$url" =~ /uploads/([a-f0-9]{32})/([^/?#]+)$ ]]; then
    printf '%s/projects/%s/uploads/%s/%s\n' "$api_base" \
      "$(wp_plugin_base_provider_gitlab_project_id "$reference")" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf '%s\n' "$url"
  fi
}

# Scope HTTP Git credentials to one configured host and one process. This works
# for private foundation sources without putting tokens in URLs or git config.
wp_plugin_base_provider_git() {
  local provider="$1"
  local api_base="$2"
  shift 2
  local token=''
  local username=''
  local web_base=''
  local basic_auth=''
  case "$provider" in
    github|github-release) token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"; username='x-access-token' ;;
    gitlab|gitlab-release)
      token="${GITLAB_TOKEN:-${CI_JOB_TOKEN:-}}"
      username='oauth2'
      if [ -z "${GITLAB_TOKEN:-}" ]; then username='gitlab-ci-token'; fi
      ;;
    *) echo "Unsupported Git authentication provider: $provider" >&2; return 1 ;;
  esac
  if [ -z "$token" ]; then
    GIT_TERMINAL_PROMPT=0 git "$@"
    return
  fi
  web_base="$(wp_plugin_base_provider_web_base "$provider" "$api_base")"
  if [ -z "$(wp_plugin_base_url_host "$web_base")" ]; then
    echo 'Provider Git authentication requires a configured HTTPS host.' >&2
    return 1
  fi
  basic_auth="$(printf '%s:%s' "$username" "$token" | base64 | tr -d '\n')"
  GIT_TERMINAL_PROMPT=0 \
    GIT_CONFIG_COUNT=3 \
    GIT_CONFIG_KEY_0="http.${web_base}/.extraheader" GIT_CONFIG_VALUE_0='' \
    GIT_CONFIG_KEY_1="http.${web_base}/.extraheader" GIT_CONFIG_VALUE_1="AUTHORIZATION: basic ${basic_auth}" \
    GIT_CONFIG_KEY_2='http.followRedirects' GIT_CONFIG_VALUE_2=false \
    git "$@"
}
