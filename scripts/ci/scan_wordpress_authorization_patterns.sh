#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

CONFIG_OVERRIDE="${1:-}"

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

SUPPRESSIONS_FILE="${WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE:-.wp-plugin-base-security-suppressions.json}"
SUPPRESSIONS_PATH="$(wp_plugin_base_resolve_path "$SUPPRESSIONS_FILE")"
SUPPRESSIONS_PRESENT='false'

if [ -f "$SUPPRESSIONS_PATH" ]; then
  SUPPRESSIONS_PRESENT='true'
  wp_plugin_base_assert_path_within_root "$SUPPRESSIONS_PATH" "Security suppressions file"
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required when $SUPPRESSIONS_FILE is present." >&2
    exit 1
  fi

  if ! jq -e '
    type == "object" and
    ((.suppressions // []) | type == "array") and
    all((.suppressions // [])[];
      (.kind | type == "string") and
      (.kind == "wp_ajax_nopriv" or .kind == "admin_post_nopriv" or .kind == "rest_permission_callback_true" or .kind == "rest_public_operation" or .kind == "rest_route_bypass") and
      (.identifier | type == "string") and
      (.path | type == "string") and
      (.justification | type == "string") and
      ((.justification | gsub("^[[:space:]]+|[[:space:]]+$"; "") | length) > 0)
    )
  ' "$SUPPRESSIONS_PATH" >/dev/null; then
    echo "Invalid suppression file format in $SUPPRESSIONS_FILE. Each suppression requires kind in {wp_ajax_nopriv, admin_post_nopriv, rest_permission_callback_true, rest_public_operation, rest_route_bypass}, identifier, path, and non-empty justification." >&2
    exit 1
  fi
fi

find_suppression_justification() {
  local kind="$1"
  local identifier="$2"
  local path="$3"

  if [ "$SUPPRESSIONS_PRESENT" != 'true' ]; then
    return 1
  fi

  jq -r \
    --arg kind "$kind" \
    --arg identifier "$identifier" \
    --arg path "$path" \
    '
      (.suppressions // [])
      | map(select(.kind == $kind and .identifier == $identifier and .path == $path))
      | if length == 0 then empty else .[0].justification end
    ' \
    "$SUPPRESSIONS_PATH"
}

declare -a php_files=()
while IFS= read -r file; do
  php_files+=("$file")
done < <(
  find "$ROOT_DIR" \
    \( -path "$ROOT_DIR/.git" -o -path "$ROOT_DIR/.github" -o -path "$ROOT_DIR/.wp-plugin-base" -o -path "$ROOT_DIR/.wp-plugin-base-quality-pack" -o -path "$ROOT_DIR/.wp-plugin-base-security-pack" -o -path "$ROOT_DIR/dist" -o -path "$ROOT_DIR/node_modules" -o -path "$ROOT_DIR/tests" -o -path "$ROOT_DIR/vendor" \) -prune \
    -o -type f -name '*.php' -print | sort
)

if [ "${#php_files[@]}" -eq 0 ]; then
  echo "WordPress authorization pattern scan skipped; no PHP files found."
  exit 0
fi

declare -a matches=()
suppressed_count=0

for file in "${php_files[@]}"; do
  relative_path="${file#"$ROOT_DIR"/}"
  if [ "$relative_path" = "$file" ]; then
    relative_path="$file"
  fi

  while IFS=$'\t' read -r kind line identifier message; do
    [ -n "$kind" ] || continue
    justification="$(find_suppression_justification "$kind" "$identifier" "$relative_path" || true)"
    if [ -n "$justification" ]; then
      echo "Suppressed $kind in $relative_path:$line ($identifier): $justification"
      suppressed_count=$((suppressed_count + 1))
      continue
    fi

    matches+=("$relative_path:$line:$message (kind=$kind, identifier=$identifier)")
  done < <(
    perl -0ne '
      while (/register_rest_route\s*\((.*?)\)\s*;/sg) {
        my $route_call = $&;
        next unless $route_call =~ /permission_callback/s;
        if ($route_call =~ /permission_callback\s*=>\s*["'"'"']__return_true["'"'"']/s) {
          my $offset = pos() - length($route_call);
          my $prefix = substr($_, 0, $offset);
          my $line = 1 + ($prefix =~ tr/\n//);
          my $identifier = "__return_true";
          if ($route_call =~ /register_rest_route\s*\(\s*["'"'"']([^"'"'"']+)["'"'"']\s*,\s*["'"'"']([^"'"'"']+)["'"'"']/s) {
            $identifier = "$1:$2";
          }
          print "rest_permission_callback_true\t$line\t$identifier\tRegistering a REST route with permission_callback => __return_true requires explicit security review.\n";
        }
      }

      while (/add_action\s*\(\s*["'"'"']wp_ajax_nopriv_([^"'"'"']+)["'"'"']/sg) {
        my $offset = pos() - length($&);
        my $prefix = substr($_, 0, $offset);
        my $line = 1 + ($prefix =~ tr/\n//);
        my $identifier = $1;
        print "wp_ajax_nopriv\t$line\t$identifier\tPublic wp_ajax_nopriv handler requires explicit nonce, input validation, and abuse-protection review.\n";
      }

      while (/add_action\s*\(\s*["'"'"']admin_post_nopriv_([^"'"'"']+)["'"'"']/sg) {
        my $offset = pos() - length($&);
        my $prefix = substr($_, 0, $offset);
        my $line = 1 + ($prefix =~ tr/\n//);
        my $identifier = $1;
        print "admin_post_nopriv\t$line\t$identifier\tPublic admin_post_nopriv handler requires explicit nonce, input validation, and abuse-protection review.\n";
      }
    ' "$file"
  )
done

if [ "${#matches[@]}" -gt 0 ]; then
  echo "Potentially unsafe public endpoint authorization patterns found:" >&2
  printf '%s\n' "${matches[@]}" >&2
  if [ "$SUPPRESSIONS_PRESENT" != 'true' ]; then
    echo "Create $SUPPRESSIONS_FILE with justified suppressions for intentional public endpoints." >&2
  else
    echo "Add a justified suppression in $SUPPRESSIONS_FILE when a public endpoint is intentional." >&2
  fi
  exit 1
fi

if [ "$suppressed_count" -gt 0 ]; then
  echo "WordPress authorization pattern scan passed with $suppressed_count justified suppression(s)."
else
  echo "WordPress authorization pattern scan passed."
fi
