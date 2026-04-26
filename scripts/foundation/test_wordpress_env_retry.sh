#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/wordpress_tooling.sh
. "$ROOT_DIR/scripts/lib/wordpress_tooling.sh"

fixture_dir="$(mktemp -d)"
attempts_file="$fixture_dir/attempts"
mode_file="$fixture_dir/mode"
stderr_file="$fixture_dir/stderr"

cleanup() {
  rm -rf "$fixture_dir"
}

trap cleanup EXIT

mkdir -p "$fixture_dir/node_modules/.bin"
printf '0\n' > "$attempts_file"
printf 'retry\n' > "$mode_file"

cat > "$fixture_dir/node_modules/.bin/wp-env" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

attempts_file="$WP_PLUGIN_BASE_RETRY_TEST_ATTEMPTS"
mode_file="$WP_PLUGIN_BASE_RETRY_TEST_MODE"

case "${1:-}" in
  start)
    attempts="$(cat "$attempts_file")"
    attempts=$((attempts + 1))
    printf '%s\n' "$attempts" > "$attempts_file"

    if [ "$(cat "$mode_file")" = "retry" ] && [ "$attempts" -eq 1 ]; then
      echo "simulated transient wp-env failure" >&2
      exit 1
    fi

    if [ "$(cat "$mode_file")" = "fail" ]; then
      echo "simulated persistent wp-env failure" >&2
      exit 1
    fi
    ;;
  stop)
    exit 0
    ;;
esac
EOF
chmod +x "$fixture_dir/node_modules/.bin/wp-env"

WP_PLUGIN_BASE_RETRY_TEST_ATTEMPTS="$attempts_file" \
WP_PLUGIN_BASE_RETRY_TEST_MODE="$mode_file" \
WP_PLUGIN_BASE_WP_ENV_START_ATTEMPTS=2 \
WP_PLUGIN_BASE_WP_ENV_RETRY_DELAY_SECONDS=0 \
  wp_plugin_base_wordpress_env_start_with_retry "$fixture_dir" --config=/tmp/wp-env-test.json 2>"$stderr_file"

if [ "$(cat "$attempts_file")" != "2" ]; then
  echo "Expected wp-env retry helper to succeed on the second attempt." >&2
  exit 1
fi

if ! grep -Fq 'simulated transient wp-env failure' "$stderr_file"; then
  echo "Expected wp-env retry helper to print the failed start stderr." >&2
  exit 1
fi

printf '0\n' > "$attempts_file"
printf 'fail\n' > "$mode_file"

if WP_PLUGIN_BASE_RETRY_TEST_ATTEMPTS="$attempts_file" \
  WP_PLUGIN_BASE_RETRY_TEST_MODE="$mode_file" \
  WP_PLUGIN_BASE_WP_ENV_START_ATTEMPTS=2 \
  WP_PLUGIN_BASE_WP_ENV_RETRY_DELAY_SECONDS=0 \
    wp_plugin_base_wordpress_env_start_with_retry "$fixture_dir" --config=/tmp/wp-env-test.json 2>"$stderr_file"; then
  echo "Expected wp-env retry helper to fail after exhausting attempts." >&2
  exit 1
fi

if [ "$(cat "$attempts_file")" != "2" ]; then
  echo "Expected wp-env retry helper to stop after the configured attempt count." >&2
  exit 1
fi

echo "wp-env retry helper tests passed."
