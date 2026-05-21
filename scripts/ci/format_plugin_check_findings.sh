#!/usr/bin/env bash

set -euo pipefail

finding_type="${1:-}"
limit="${2:-10}"

if [[ ! "$finding_type" =~ ^[A-Z_]+$ ]]; then
  echo "Usage: $0 ERROR|WARNING [limit]" >&2
  exit 1
fi

if [[ ! "$limit" =~ ^[0-9]+$ ]] || [ "$limit" -lt 1 ]; then
  echo "Plugin Check finding limit must be a positive integer: $limit" >&2
  exit 1
fi

jq -r --arg finding_type "$finding_type" --argjson limit "$limit" '
  [
    .[]
    | select(.type == $finding_type)
  ][0:$limit][]
  | [
      (.code // "unknown_code"),
      (
        (if (.file // "") == "" then "(no file)" else (.file // "") end)
        + (
          if (((.line // 0) | tonumber? // 0) > 0)
          then ":" + ((.line // 0) | tostring)
          else ""
          end
        )
      ),
      (
        (.message // "")
        | gsub("<br[[:space:]]*/?>"; " ")
        | gsub("<[^>]+>"; "")
        | gsub("&lt;"; "<")
        | gsub("&gt;"; ">")
        | gsub("&amp;"; "&")
        | gsub("[[:space:]]+"; " ")
        | gsub("^[[:space:]]+|[[:space:]]+$"; "")
      )
    ]
  | @tsv
' | while IFS=$'\t' read -r code location message; do
  printf -- '- %s at %s: %s\n' "$code" "$location" "$message"
done
