#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"

CONFIG_OVERRIDE="${1:-}"

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

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

matches="$(
  perl -0ne '
    while (/register_rest_route\s*\((.*?)\)\s*;/sg) {
      my $route_call = $&;
      next unless $route_call =~ /permission_callback/s;
      if ($route_call =~ /permission_callback\s*=>\s*["'"'"']__return_true["'"'"']/s) {
        my $offset = pos() - length($route_call);
        my $prefix = substr($_, 0, $offset);
        my $line = 1 + ($prefix =~ tr/\n//);
        print "$ARGV:$line:Registering a REST route with permission_callback => __return_true requires explicit security review.\n";
      }
    }
  ' "${php_files[@]}"
)"

if [ -n "$matches" ]; then
  echo "Potentially unsafe REST authorization patterns found:" >&2
  printf '%s' "$matches" >&2
  exit 1
fi

echo "WordPress authorization pattern scan passed."
