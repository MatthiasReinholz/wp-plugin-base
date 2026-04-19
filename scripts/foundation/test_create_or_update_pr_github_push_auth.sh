#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

fixture_repo="$(mktemp -d)"
fixture_origin="$(mktemp -d)"
helper_dir="$(mktemp -d)"
pr_output="$(mktemp)"
auth_marker="$(mktemp)"

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
scheme="https:"
expected_config="url.\${scheme}//x-access-token:fixture-token"
expected_config="\${expected_config}@github.com/.insteadOf=\${scheme}//github.com/"

saw_push=false
saw_auth=false
for arg in "\$@"; do
  if [ "\$arg" = "push" ]; then
    saw_push=true
  fi
  if [ "\$arg" = "\$expected_config" ]; then
    saw_auth=true
  fi
done

if [ "\$saw_push" = true ] && [ "\$saw_auth" = true ]; then
  : > "\$auth_marker"
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
  echo "create_or_update_pr did not inject GitHub token auth into git push." >&2
  exit 1
fi

if ! grep -Fxq 'pull_request_operation=created' "$pr_output"; then
  echo "Expected PR creation when staged changes were present." >&2
  exit 1
fi

echo "create_or_update_pr GitHub push auth test passed."
