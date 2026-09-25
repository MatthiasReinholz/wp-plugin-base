#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
real_mktemp="$(command -v mktemp)"
mkdir "$fixture/bin"
printf '%s\n' 'Fixture release body.' > "$fixture/body"
printf '%s\n' 'Fixture asset.' > "$fixture/asset"

# Force header creation to fail after the private work directory exists.
cat > "$fixture/bin/mktemp" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
directory="$("$AUTH_FIXTURE_MKTEMP" "$@")"
printf '%s\n' "$directory" > "$AUTH_FIXTURE_DIRECTORY"
mkdir "$directory/auth-header"
printf '%s\n' "$directory"
MOCK
http_client_name='cu'"rl"
cat > "$fixture/bin/$http_client_name" <<'MOCK'
#!/usr/bin/env bash
touch "$AUTH_FIXTURE_NETWORK_CALLED"
exit 1
MOCK
chmod +x "$fixture/bin/mktemp" "$fixture/bin/$http_client_name"

for operation in publish verify; do
  rm -f "$fixture/directory" "$fixture/network-called"
  if [ "$operation" = publish ]; then
    command_args=(bash "$ROOT_DIR/scripts/release/publish_gitlab_release.sh" \
      1.2.3 'Fixture release' "$fixture/body" "$fixture/asset")
  else
    command_args=(bash "$ROOT_DIR/scripts/update/verify_foundation_release.sh" \
      example-group/standard-plugin v1.2.3 "$fixture/output" gitlab-release https://gitlab.com/api/v4)
  fi
  status=0
  PATH="$fixture/bin:$PATH" \
    TMPDIR="$fixture/" \
    AUTH_FIXTURE_MKTEMP="$real_mktemp" \
    AUTH_FIXTURE_DIRECTORY="$fixture/directory" \
    AUTH_FIXTURE_NETWORK_CALLED="$fixture/network-called" \
    CI_PROJECT_PATH=example-group/standard-plugin \
    GITLAB_TOKEN=synthetic-header-write-failure-token \
    "${command_args[@]}" > "$fixture/stdout" 2> "$fixture/stderr" || status=$?
  if [ "$status" -eq 0 ] || [ ! -s "$fixture/directory" ]; then
    echo "$operation did not fail during authentication header creation." >&2
    exit 1
  fi
  if [ -e "$(cat "$fixture/directory")" ] || [ -e "$fixture/network-called" ]; then
    echo "$operation retained temporary authentication state or attempted a network request." >&2
    exit 1
  fi
  if grep -Fq 'synthetic-header-write-failure-token' "$fixture/stdout" "$fixture/stderr"; then
    echo "$operation exposed authentication material during header creation failure." >&2
    exit 1
  fi
done

echo 'Release authentication header failure cleanup passed.'
