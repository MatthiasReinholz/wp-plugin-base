#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/wordpress_tooling.sh
. "$ROOT_DIR/scripts/lib/wordpress_tooling.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
calls="$fixture/calls"
result=0
wp_plugin_base_wordpress_env() {
  printf '%s\n' "$WP_ENV_HOME" "$BUILDX_CONFIG" "$NPM_CONFIG_CACHE" "$@" >> "$calls"
  return "$result"
}

create_environment() {
  environment="$fixture/$1"
  mkdir -p "$environment/tools" "$environment/home" "$environment/cache" "$environment/buildx"
  printf '%s\n' '{}' > "$environment/config.json"
  printf '%s\n' 'Diagnostic output' > "$environment/start.log"
}

cleanup_environment() {
  wp_plugin_base_cleanup_temporary_wordpress_env "$environment/tools" "$environment/home" "$environment/config.json" \
    "$environment/cache" "$environment/buildx" "$1" "$environment/start.log"
}

create_environment 'successful cleanup'
cleanup_environment true
cat > "$fixture/expected-calls" <<EOF_CALLS
$environment/home
$environment/buildx
$environment/cache
$environment/tools
cleanup
--force
--config=$environment/config.json
EOF_CALLS
cmp "$calls" "$fixture/expected-calls"
if [ -n "$(ls -A "$environment")" ]; then
  echo 'Successful cleanup left temporary inputs behind.' >&2
  exit 1
fi

create_environment 'failed cleanup'
result=1
if cleanup_environment true 2> "$fixture/recovery-message"; then
  echo 'Cleanup failure was reported as success.' >&2
  exit 1
fi
for retained in tools home config.json cache buildx start.log; do
  test -e "$environment/$retained"
done
grep -Fq 'retaining configuration and tools for recovery' "$fixture/recovery-message"
grep -Fq 'cleanup --force --config=' "$fixture/recovery-message"

create_environment 'not started'
cp "$calls" "$fixture/prior-calls"
cleanup_environment false
cmp "$calls" "$fixture/prior-calls"
if [ -n "$(ls -A "$environment")" ]; then
  echo 'Unstarted environment inputs were not removed.' >&2
  exit 1
fi

for script in scripts/ci/run_plugin_check.sh scripts/release/generate_pot.sh; do
  grep -Fq 'wp_env_start_attempted=true' "$ROOT_DIR/$script"
  grep -Fq 'if ! wp_plugin_base_cleanup_temporary_wordpress_env ' "$ROOT_DIR/$script"
  sed -n '/^cleanup() {$/,/^}$/p' "$ROOT_DIR/$script" > "$fixture/exit-trap.sh"
  for scenario in '0 0 0' '0 1 1' '7 1 7'; do
    read -r original cleanup_result expected <<< "$scenario"
    actual=0
    bash -c '
      set -euo pipefail
      wp_env_tools_dir="" wp_env_home="" wp_env_config="" npm_cache_dir="" buildx_config_dir="" wp_env_start_attempted=true wp_env_start_log=""
      cleanup_result="$2"
      wp_plugin_base_cleanup_temporary_wordpress_env() { return "$cleanup_result"; }
      source "$3"
      trap cleanup EXIT
      exit "$1"
    ' bash "$original" "$cleanup_result" "$fixture/exit-trap.sh" || actual="$?"
    if [ "$actual" -ne "$expected" ]; then
      echo "Unexpected cleanup exit status for $script: $actual, expected $expected" >&2
      exit 1
    fi
  done
done
echo 'Temporary WordPress environment cleanup tests passed.'
