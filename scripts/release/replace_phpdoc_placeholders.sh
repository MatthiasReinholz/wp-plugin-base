#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "PHPDoc version placeholder replacement" git perl

VERSION="${1:-}"
CONFIG_OVERRIDE="${2:-}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z [config-path]" >&2
  exit 1
fi

wp_plugin_base_load_config "$CONFIG_OVERRIDE"

placeholder="${PHPDOC_VERSION_PLACEHOLDER:-NEXT}"
if [ -z "$placeholder" ]; then
  echo "PHPDOC_VERSION_PLACEHOLDER cannot be empty." >&2
  exit 1
fi

escaped_placeholder="$(printf '%s' "$placeholder" | sed -e 's/[.[\*^$+?{}|()]/\\&/g')"
replacement_count=0
current_temp_file=""

wp_plugin_base_cleanup_phpdoc_placeholder_replacement() {
  if [ -n "$current_temp_file" ]; then
    rm -f "$current_temp_file"
  fi
}

trap wp_plugin_base_cleanup_phpdoc_placeholder_replacement EXIT

should_skip_path() {
  local path="$1"
  local exclude=""

  case "$path" in
    vendor/*|node_modules/*|.git/*|.wp-plugin-base/*)
      return 0
      ;;
  esac

  if [ -n "${PACKAGE_EXCLUDE:-}" ]; then
    while IFS= read -r exclude; do
      [ -n "$exclude" ] || continue
      exclude="${exclude#./}"
      exclude="${exclude#/}"
      case "$path" in
        "$exclude"|"$exclude"/*)
          return 0
          ;;
      esac
    done < <(wp_plugin_base_csv_to_lines "$PACKAGE_EXCLUDE")
  fi

  return 1
}

if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  php_files_cmd=(git -C "$ROOT_DIR" ls-files '*.php')
else
  php_files_cmd=(find "$ROOT_DIR" -type f -name '*.php' -print)
fi

while IFS= read -r php_file; do
  [ -n "$php_file" ] || continue
  if [[ "$php_file" = "$ROOT_DIR/"* ]]; then
    php_file="${php_file#"$ROOT_DIR"/}"
  fi
  if should_skip_path "$php_file"; then
    continue
  fi

  absolute_path="$ROOT_DIR/$php_file"
  [ -f "$absolute_path" ] || continue

  file_before="$(mktemp)"
  current_temp_file="$file_before"
  cp "$absolute_path" "$file_before"
  perl -0pi -e "s/(\@since[[:space:]]+)${escaped_placeholder}(?=([[:space:]]|\$))/\${1}${VERSION}/g; s/(\@version[[:space:]]+)${escaped_placeholder}(?=([[:space:]]|\$))/\${1}${VERSION}/g" "$absolute_path"
  if ! cmp -s "$file_before" "$absolute_path"; then
    replacement_count=$((replacement_count + 1))
  fi
  rm -f "$file_before"
  # Disarm the EXIT trap for the temp file that was already removed.
  current_temp_file=""
done < <("${php_files_cmd[@]}")

echo "Updated PHPDoc placeholders in ${replacement_count} PHP file(s)."
