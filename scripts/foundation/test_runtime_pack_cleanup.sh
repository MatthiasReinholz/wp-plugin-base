#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
runner="$ROOT_DIR/scripts/foundation/test_runtime_packs_wordpress.sh"
sed -n '/^cleanup() {$/,/^}$/p' "$runner" > "$fixture/cleanup.sh"
mkdir -p "$fixture/unrelated environment"
printf 'preserve\n' > "$fixture/unrelated environment/marker"

cat > "$fixture/run-case.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
scenario="$1"
original_status="$2"
case_dir="$3"
calls="$4"
cleanup_source="$5"
wp_env_home="$case_dir/home"
wp_env_tools_dir="$case_dir/tools"
npm_cache_dir="$case_dir/npm cache"
buildx_config_dir="$case_dir/buildx"
mkdir -p "$wp_env_home" "$wp_env_tools_dir/node_modules/.bin" "$npm_cache_dir" "$buildx_config_dir"
if [ "$scenario" != missing-tool ]; then
  printf '#!/usr/bin/env bash\nexit 0\n' > "$wp_env_tools_dir/node_modules/.bin/wp-env"
  chmod +x "$wp_env_tools_dir/node_modules/.bin/wp-env"
fi
declare -a wp_env_configs=()
declare -a wp_env_started_configs=()
declare -a fixture_dirs=()
declare -a start_logs=()
if [ "$scenario" != empty-arrays ]; then
  for name in first second unstarted; do
    config="$case_dir/$name config.json"
    printf '{}\n' > "$config"
    mkdir -p "$case_dir/$name fixture"
    printf 'start diagnostics\n' > "$case_dir/$name start.log"
    wp_env_configs+=("$config")
    fixture_dirs+=("$case_dir/$name fixture")
    start_logs+=("$case_dir/$name start.log")
    if [ "$scenario" != not-started ] && [ "$name" != unstarted ]; then
      wp_env_started_configs+=("$config")
    fi
  done
fi
wp_plugin_base_wordpress_env() {
  test "$WP_ENV_HOME" = "$wp_env_home" || return 90
  test "$BUILDX_CONFIG" = "$buildx_config_dir" || return 90
  test "$NPM_CONFIG_CACHE" = "$npm_cache_dir" || return 90
  test "$1" = "$wp_env_tools_dir" || return 90
  test "$2" = cleanup || return 90
  test "$3" = --force || return 90
  test -f "${4#--config=}" || return 90
  # Shared recovery inputs must still exist when the second cleanup is called.
  test -d "$wp_env_tools_dir" || return 90
  test -d "$wp_env_home" || return 90
  test -d "$case_dir/first fixture" || return 90
  printf '%s\n' "$4" >> "$calls"
  if { [ "$scenario" = partial-failure ] && [ "$4" = "--config=$case_dir/first config.json" ]; } ||
    { [ "$scenario" = second-failure ] && [ "$4" = "--config=$case_dir/second config.json" ]; }; then
    return 1
  fi
}
# shellcheck disable=SC1090 -- Source only the trap extracted from the real runner.
source "$cleanup_source"
trap cleanup EXIT
exit "$original_status"
SH

for case_spec in \
  'success 0 0' \
  'success 1 1' \
  'second-failure 0 1' \
  'partial-failure 0 1' \
  'partial-failure 1 1' \
  'partial-failure 7 7' \
  'success 7 7' \
  'not-started 0 0' \
  'not-started 1 1' \
  'empty-arrays 7 7' \
  'missing-tool 0 1'
do
  read -r scenario original expected <<< "$case_spec"
  case_dir="$fixture/$scenario status $original"
  calls="$fixture/$scenario-$original.calls"
  output="$fixture/$scenario-$original.output"
  : > "$calls"
  actual=0
  bash "$fixture/run-case.sh" "$scenario" "$original" "$case_dir" "$calls" "$fixture/cleanup.sh" > "$output" 2>&1 || actual="$?"
  if [ "$actual" -ne "$expected" ]; then
    cat "$output" >&2
    echo "Cleanup returned $actual for $case_spec, expected $expected." >&2
    exit 1
  fi
  case "$scenario" in
    success|partial-failure|second-failure)
      printf '%s\n' "--config=$case_dir/first config.json" "--config=$case_dir/second config.json" > "$fixture/expected-calls"
      cmp "$calls" "$fixture/expected-calls"
      ;;
    *) test ! -s "$calls" ;;
  esac
  case "$scenario" in
    partial-failure|second-failure|missing-tool)
      for retained in home tools 'npm cache' buildx 'first config.json' 'second config.json' 'unstarted config.json' 'first fixture' 'second fixture' 'first start.log'; do
        test -e "$case_dir/$retained"
      done
      grep -Fq 'Retaining all temporary configurations' "$output"
      grep -Fq 'cleanup --force --config=' "$output"
      ;;
    *) test -z "$(ls -A "$case_dir")" ;;
  esac
  grep -Fxq preserve "$fixture/unrelated environment/marker"
done

# The registration must precede the actual start call, including partial starts.
registration_line="$(grep -nF 'wp_env_started_configs+=("$wp_env_config")' "$runner" | cut -d: -f1)"
start_line="$(grep -nF 'wp_plugin_base_wordpress_env "$wp_env_tools_dir" start --config=' "$runner" | cut -d: -f1)"
test "$registration_line" -lt "$start_line"
echo 'Runtime WordPress cleanup ownership, recovery and exit-status contracts passed.'
