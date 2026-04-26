#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

fixture_repo="$(mktemp -d)"
fixture_origin="$(mktemp -d)"
helper_dir="$(mktemp -d)"
pr_output="$(mktemp)"
auth_marker="$(mktemp)"
expected_auth_header="AUTHORIZATION: basic $(printf 'x-access-token:%s' 'fixture-token' | base64 | tr -d '\n')"

cleanup() {
  rm -rf "$fixture_repo" "$fixture_origin" "$helper_dir" "$pr_output" "$auth_marker"
}
trap cleanup EXIT

real_git="$(command -v git)"

git init --bare -q "$fixture_origin"
git -C "$fixture_repo" init -q
git -C "$fixture_repo" config user.email "fixture@example.com"
git -C "$fixture_repo" config user.name "Fixture"

echo 'root' > "$fixture_repo/README.md"
git -C "$fixture_repo" add README.md
git -C "$fixture_repo" commit -qm "init"
git -C "$fixture_repo" branch -M main
git -C "$fixture_repo" remote add origin "$fixture_origin"
git -C "$fixture_repo" push -q -u origin main

cat > "$helper_dir/body.md" <<'BODYEOF'
fixture body
BODYEOF
mkdir -p "$helper_dir/bin"
cat > "$helper_dir/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  echo '[]'
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "create" ]; then
  echo 'https://github.com/example/repo/pull/1'
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "edit" ]; then
  exit 0
fi
echo "Unexpected gh invocation: $*" >&2
exit 1
GHEOF
chmod +x "$helper_dir/bin/gh"

cat > "$helper_dir/bin/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail

real_git="$real_git"
auth_marker="$auth_marker"
argv_log="$helper_dir/git-argv.log"
expected_header="$expected_auth_header"

saw_push=false
for arg in "\$@"; do
  printf '%s\n' "\$arg" >> "\$argv_log"
  if [ "\$arg" = "push" ]; then
    saw_push=true
  fi
done

if [ "\$saw_push" = true ]; then
  configured_header=""
  if [ "\${GIT_CONFIG_COUNT:-0}" = "1" ] && [ "\${GIT_CONFIG_KEY_0:-}" = "http.https://github.com/.extraheader" ]; then
    configured_header="\${GIT_CONFIG_VALUE_0:-}"
  fi
  if [ "\$configured_header" = "\$expected_header" ]; then
    : > "\$auth_marker"
  fi
fi

exec "\$real_git" "\$@"
EOF
chmod +x "$helper_dir/bin/git"

printf '%s\n' 'release prep' >> "$fixture_repo/README.md"

(
  cd "$fixture_repo"
  PATH="$helper_dir/bin:$PATH" \
    GITHUB_REPOSITORY="example/repo" \
    GITHUB_REPOSITORY_OWNER="example" \
    GITHUB_TOKEN="fixture-token" \
    GITHUB_OUTPUT="$pr_output" \
    bash "$ROOT_DIR/scripts/update/create_or_update_pr.sh" \
      "release/v1.6.4" \
      "main" \
      "Foundation release v1.6.4" \
      "Foundation release v1.6.4" \
      "$helper_dir/body.md"
)

if [ ! -f "$auth_marker" ]; then
  echo "create_or_update_pr did not configure GitHub token auth before git push." >&2
  exit 1
fi

if grep -Fq 'fixture-token' "$helper_dir/git-argv.log"; then
  echo "create_or_update_pr leaked the GitHub token through git process arguments." >&2
  exit 1
fi

if grep -Fq "$expected_auth_header" "$helper_dir/git-argv.log"; then
  echo "create_or_update_pr leaked the GitHub auth header through git process arguments." >&2
  exit 1
fi

if git -C "$fixture_repo" config --local --get-regexp '^url\\..*\\.insteadOf$|^http\\..*\\.extraheader$' | grep -Eq 'fixture-token|AUTHORIZATION: basic'; then
  echo "create_or_update_pr persisted GitHub token authentication in local git config." >&2
  exit 1
fi

if ! grep -Fxq 'pull_request_operation=created' "$pr_output"; then
  echo "Expected PR creation when staged changes were present." >&2
  exit 1
fi

echo "create_or_update_pr GitHub push auth test passed."
