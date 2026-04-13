#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

CONFIG_OVERRIDE="${1:-}"

wp_plugin_base_require_commands "REST operation contract validation" php jq
wp_plugin_base_load_config "$CONFIG_OVERRIDE"

BOOTSTRAP_PATH="$(wp_plugin_base_resolve_path "includes/rest-operations/bootstrap.php")"
SUPPRESSIONS_PATH="$(wp_plugin_base_resolve_path "$WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE")"

if [ ! -f "$BOOTSTRAP_PATH" ]; then
  echo "REST operations bootstrap not found: includes/rest-operations/bootstrap.php" >&2
  exit 1
fi

operations_json="$(
  php -r '
define( "ABSPATH", "/" );
if ( ! function_exists( "__" ) ) {
  function __( $text ) {
    return $text;
  }
}
$manifest = require $argv[1];
if ( ! is_array( $manifest ) ) {
  fwrite( STDERR, "REST operations bootstrap must return an array.\n" );
  exit( 1 );
}

foreach ( $manifest as $index => $operation ) {
  if ( ! is_array( $operation ) ) {
    fwrite( STDERR, "REST operation at index {$index} is not an array.\n" );
    exit( 1 );
  }

  if ( empty( $operation["callback"] ) || ! is_callable( $operation["callback"] ) ) {
    $operation_id = isset( $operation["id"] ) ? $operation["id"] : "#{$index}";
    fwrite( STDERR, "REST operation {$operation_id} must declare a callable callback.\n" );
    exit( 1 );
  }

  if ( ! empty( $operation["capability_callback"] ) && ! is_callable( $operation["capability_callback"] ) ) {
    $operation_id = isset( $operation["id"] ) ? $operation["id"] : "#{$index}";
    fwrite( STDERR, "REST operation {$operation_id} declares a non-callable capability_callback.\n" );
    exit( 1 );
  }
}

echo json_encode( $manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES );
' "$BOOTSTRAP_PATH"
)"

if [ -z "$operations_json" ]; then
  echo "REST operations bootstrap returned an empty manifest." >&2
  exit 1
fi

find_suppression_justification() {
  local kind="$1"
  local identifier="$2"
  local path="$3"

  if [ ! -f "$SUPPRESSIONS_PATH" ]; then
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

php_file_has_register_rest_route_call() {
  local file_path="$1"

  php -r '
$code = file_get_contents($argv[1]);
if ($code === false) {
  fwrite(STDERR, "Unable to read PHP file.\n");
  exit(2);
}

$tokens = token_get_all($code);
$count = count($tokens);
for ($i = 0; $i < $count; $i++) {
  $token = $tokens[$i];
  if (!is_array($token)) {
    continue;
  }

  if ($token[0] !== T_STRING || strcasecmp($token[1], "register_rest_route") !== 0) {
    continue;
  }

  $j = $i + 1;
  while ($j < $count) {
    $next = $tokens[$j];
    if (is_array($next) && in_array($next[0], array(T_WHITESPACE, T_COMMENT, T_DOC_COMMENT), true)) {
      $j++;
      continue;
    }

    if ($next === "(") {
      echo "true";
      exit(0);
    }

    break;
  }
}

echo "false";
' "$file_path"
}

if ! jq -e '
  type == "array" and
  length > 0 and
  all(
    .[];
    def callable:
      (type == "string" and length > 0) or
      (type == "array" and length == 2 and all(.[]; type == "string" and length > 0));
    def capability_declared:
      (
        (.capability | type) == "string" and (.capability | length > 0)
      ) or (
        (.capability | type) == "array" and (.capability | length > 0) and all(.capability[]; type == "string" and length > 0)
      );
    type == "object" and
    (.id | type == "string" and length > 0) and
    (.route | type == "string" and test("^/")) and
    (.callback | callable) and
    (
      (.source_file // null) == null or
      (.source_file | type == "string" and length > 0)
    ) and
    (
      (.methods | type == "string" and length > 0) or
      (.methods | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
    ) and
    (.visibility | type == "string" and (. == "public" or . == "authenticated" or . == "admin")) and
    (
      .visibility == "public" or
      (
        (capability_declared or ((.capability_callback // null) != null and (.capability_callback | callable))) and
        (.required_scopes | type == "array" and length > 0 and all(.[]; type == "string" and length > 0))
      )
    ) and
    (
      (.ability // null) == null or
      (.ability | type == "object")
    )
  )
' <<<"$operations_json" >/dev/null; then
  echo "REST operations manifest is invalid. Each operation must declare id, route, methods, visibility, and authorization metadata." >&2
  exit 1
fi

duplicate_ids="$(
  jq -r '
    group_by(.id)
    | map(select(length > 1) | .[0].id)
    | .[]
  ' <<<"$operations_json"
)"
if [ -n "$duplicate_ids" ]; then
  echo "REST operations manifest contains duplicate operation ids:" >&2
  printf '%s\n' "$duplicate_ids" >&2
  exit 1
fi

duplicate_routes="$(
  jq -r '
    map(.route + "|" + (if (.methods | type) == "array" then (.methods | sort | join(",")) else .methods end))
    | group_by(.)
    | map(select(length > 1) | .[0])
    | .[]
  ' <<<"$operations_json"
)"
if [ -n "$duplicate_routes" ]; then
  echo "REST operations manifest contains duplicate route+method entries:" >&2
  printf '%s\n' "$duplicate_routes" >&2
  exit 1
fi

declare -a php_files=()
while IFS= read -r file; do
  php_files+=("$file")
done < <(
  find "$ROOT_DIR" \
    \( -path "$ROOT_DIR/.git" -o -path "$ROOT_DIR/.github" -o -path "$ROOT_DIR/.wp-plugin-base" -o -path "$ROOT_DIR/dist" -o -path "$ROOT_DIR/node_modules" -o -path "$ROOT_DIR/vendor" \) -prune \
    -o -type f -name '*.php' -print | sort
)

declare -a route_bypass_matches=()
for file in "${php_files[@]}"; do
  relative_path="${file#"$ROOT_DIR"/}"
  case "$relative_path" in
    tests/*|vendor/*|lib/*)
      continue
      ;;
  esac

  if [ "$(php_file_has_register_rest_route_call "$file")" = "true" ]; then
    justification="$(find_suppression_justification "rest_route_bypass" "register_rest_route" "$relative_path" || true)"
    if [ -n "$justification" ]; then
      echo "Suppressed rest_route_bypass in $relative_path: $justification"
      continue
    fi

    route_bypass_matches+=("$relative_path")
  fi
done

if [ "${#route_bypass_matches[@]}" -gt 0 ]; then
  echo "REST operations pack requires routes to be declared through the approved operation registry unless a justified rest_route_bypass suppression is present. Raw register_rest_route calls found in:" >&2
  printf '%s\n' "${route_bypass_matches[@]}" >&2
  exit 1
fi

public_operation_ids="$(
  jq -r '.[] | select(.visibility == "public") | .id' <<<"$operations_json"
)"

if [ -n "$public_operation_ids" ]; then
  if [ ! -f "$SUPPRESSIONS_PATH" ]; then
    echo "Public REST operations require $WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE to declare justified rest_public_operation suppressions." >&2
    exit 1
  fi

  while IFS= read -r operation_id; do
    [ -n "$operation_id" ] || continue
    operation_source_path="$(
      jq -r \
        --arg identifier "$operation_id" \
        '.[] | select(.id == $identifier) | (.source_file // "includes/rest-operations/bootstrap.php")' \
        <<<"$operations_json"
    )"
    if ! jq -e \
      --arg identifier "$operation_id" \
      --arg path "$operation_source_path" \
      '
        (.suppressions // [])
        | any(.[]; .kind == "rest_public_operation" and .identifier == $identifier and .path == $path)
      ' \
      "$SUPPRESSIONS_PATH" >/dev/null; then
      echo "Public REST operation ${operation_id} is missing a justified rest_public_operation suppression entry in $WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE." >&2
      exit 1
    fi
  done <<<"$public_operation_ids"
fi

echo "REST operation contract validation passed."
