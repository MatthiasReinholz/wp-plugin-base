#!/usr/bin/env bash

set -euo pipefail

raw_output="$(cat)"
json_payload="$raw_output"

if [ -z "$json_payload" ]; then
  json_payload='[]'
fi

if printf '%s\n' "$json_payload" | tr -d '\r' | grep -Eq '^[[:space:]]*Success: Checks complete\. No errors found\.[[:space:]]*$'; then
  json_payload='[]'
fi

if ! printf '%s\n' "$json_payload" | jq -e 'type == "array"' >/dev/null 2>&1; then
  extracted_payload="$(
    printf '%s\n' "$raw_output" | perl -0ne '
      if (/(\[[\s\S]*\])(?:\s*✔ Ran|\s*\z)/) {
        print $1;
        exit 0;
      }
      exit 1;
    '
  )" || true

  if [ -n "${extracted_payload:-}" ]; then
    json_payload="$extracted_payload"
  fi
fi

if ! printf '%s\n' "$json_payload" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "Plugin Check output could not be normalized to a JSON array." >&2
  exit 1
fi

printf '%s\n' "$json_payload"
