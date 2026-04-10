#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "release metadata update" git perl

VERSION="${1:-}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 x.y.z [config-path]" >&2
  exit 1
fi

wp_plugin_base_load_config "${2:-}"
wp_plugin_base_require_vars MAIN_PLUGIN_FILE README_FILE

PLUGIN_FILE="$(wp_plugin_base_resolve_path "$MAIN_PLUGIN_FILE")"
README_PATH="$(wp_plugin_base_resolve_path "$README_FILE")"
NOTES_FILE="$(mktemp)"
README_TMP="$(mktemp)"
CHANGELOG_MARKER="== ${CHANGELOG_HEADING} =="

cleanup() {
  rm -f "$NOTES_FILE" "$README_TMP"
}

trap cleanup EXIT

perl -0pi -e "s/^ \\* Version: .*\$/ * Version: $VERSION/m; s/^Version: .*\$/Version: $VERSION/m" "$PLUGIN_FILE"

if grep -q "^Version: " "$README_PATH"; then
  perl -0pi -e "s/^Version: .*\$/Version: $VERSION/m" "$README_PATH"
fi

if grep -q "^Stable tag: " "$README_PATH"; then
  perl -0pi -e "s/^Stable tag: .*\$/Stable tag: $VERSION/m" "$README_PATH"
fi

if [ -n "${VERSION_CONSTANT_NAME:-}" ]; then
  perl -0pi -e "s/define\\(\\s*['\\\"]${VERSION_CONSTANT_NAME}['\\\"]\\s*,\\s*['\\\"][^'\\\"]+['\\\"]\\s*\\);/define('${VERSION_CONSTANT_NAME}', '${VERSION}');/m" "$PLUGIN_FILE"
fi

PACKAGE_JSON="$(wp_plugin_base_resolve_path "package.json")"
if [ -f "$PACKAGE_JSON" ]; then
  wp_plugin_base_require_commands "package.json version sync" jq
  if jq -e 'has("version") and (.version | type == "string")' "$PACKAGE_JSON" >/dev/null 2>&1; then
    jq --arg v "$VERSION" '.version = $v' "$PACKAGE_JSON" > "${PACKAGE_JSON}.tmp"
    mv "${PACKAGE_JSON}.tmp" "$PACKAGE_JSON"
  fi
fi

PACKAGE_LOCK="$(wp_plugin_base_resolve_path "package-lock.json")"
if [ -f "$PACKAGE_LOCK" ]; then
  wp_plugin_base_require_commands "package-lock.json version sync" jq
  if jq -e 'has("version") and (.version | type == "string")' "$PACKAGE_LOCK" >/dev/null 2>&1; then
    jq --arg v "$VERSION" '
      .version = $v
      | if (.packages | type) == "object" and (.packages[""] | type) == "object" and (.packages[""] | has("version"))
        then .packages[""].version = $v
        else .
        end
    ' "$PACKAGE_LOCK" > "${PACKAGE_LOCK}.tmp"
    mv "${PACKAGE_LOCK}.tmp" "$PACKAGE_LOCK"
  fi
fi

if ! grep -q "^= $VERSION =$" "$README_PATH"; then
  bash "$SCRIPT_DIR/generate_release_notes.sh" "$VERSION" > "$NOTES_FILE"

  if ! grep -q "^${CHANGELOG_MARKER}$" "$README_PATH"; then
    echo "Missing changelog heading in $README_FILE: ${CHANGELOG_MARKER}" >&2
    exit 1
  fi

  while IFS= read -r line; do
    printf '%s\n' "$line" >> "$README_TMP"

    if [ "$line" = "$CHANGELOG_MARKER" ]; then
      printf '\n= %s =\n' "$VERSION" >> "$README_TMP"
      cat "$NOTES_FILE" >> "$README_TMP"
      printf '\n' >> "$README_TMP"
    fi
  done < "$README_PATH"

  mv "$README_TMP" "$README_PATH"
fi

if [ -n "${POT_FILE:-}" ]; then
  POT_PATH="$(wp_plugin_base_resolve_path "$POT_FILE")"

  if [ -f "$POT_PATH" ]; then
    PROJECT_NAME="${POT_PROJECT_NAME:-${PLUGIN_NAME:-Plugin}}"
    perl -0pi -e "s/Project-Id-Version: .*\\\\n/Project-Id-Version: ${PROJECT_NAME} ${VERSION}\\\\n/" "$POT_PATH"
  fi
fi

if wp_plugin_base_is_true "${PHPDOC_VERSION_REPLACEMENT_ENABLED:-false}"; then
  bash "$SCRIPT_DIR/replace_phpdoc_placeholders.sh" "$VERSION" "${2:-}"
fi

if wp_plugin_base_is_true "${CHANGELOG_MD_SYNC_ENABLED:-false}"; then
  CHANGELOG_MD_PATH="$(wp_plugin_base_resolve_path "CHANGELOG.md")"
  if [ -f "$CHANGELOG_MD_PATH" ] && ! grep -qE "^## (v)?${VERSION}$" "$CHANGELOG_MD_PATH"; then
    if [ ! -s "$NOTES_FILE" ]; then
      readme_notes="$(
        awk -v version="$VERSION" '
          $0 == "= " version " =" { in_section=1; next }
          in_section && /^= .* =$/ { exit }
          in_section { print }
        ' "$README_PATH"
      )"
      if [ -n "$readme_notes" ]; then
        printf '%s\n' "$readme_notes" > "$NOTES_FILE"
      else
        bash "$SCRIPT_DIR/generate_release_notes.sh" "$VERSION" "${2:-}" > "$NOTES_FILE"
      fi
    fi

    CHANGELOG_TMP="$(mktemp)"
    if awk -v ver="$VERSION" -v notes_file="$NOTES_FILE" '
      BEGIN { inserted=0; prefix="v" }
      /^## (v)?[0-9]+\.[0-9]+\.[0-9]+$/ && !inserted {
        if ($2 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/) {
          prefix="v"
        } else {
          prefix=""
        }
        printf "## %s%s\n\n", prefix, ver
        while ((getline line < notes_file) > 0) print line
        printf "\n"
        inserted=1
      }
      { print }
      END { if (!inserted) exit 3 }
    ' "$CHANGELOG_MD_PATH" > "$CHANGELOG_TMP"; then
      mv "$CHANGELOG_TMP" "$CHANGELOG_MD_PATH"
    else
      status="$?"
      rm -f "$CHANGELOG_TMP"
      if [ "$status" -eq 3 ]; then
        echo "Skipped CHANGELOG.md sync: no supported version heading found in CHANGELOG.md." >&2
      else
        exit "$status"
      fi
    fi
  fi
fi

echo "Updated release metadata to $VERSION."
