#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

fixture_repo="$(mktemp -d)"
helper_dir="$(mktemp -d)"
pr_output="$(mktemp)"
auth_log="$(mktemp)"

cleanup() {
  rm -rf "$fixture_repo" "$helper_dir" "$pr_output" "$auth_log"
}
trap cleanup EXIT

git -C "$fixture_repo" init -q
git -C "$fixture_repo" config user.email "fixture@example.com"
git -C "$fixture_repo" config user.name "Fixture"
git -C "$fixture_repo" remote add origin "https://github.com/example/repo.git"

echo 'root' > "$fixture_repo/README.md"
git -C "$fixture_repo" add README.md
git -C "$fixture_repo" commit -qm "init"
git -C "$fixture_repo" branch -M main

git -C "$fixture_repo" config --local --add http.https://github.com/.extraheader "AUTHORIZATION: basic old-header"
git -C "$fixture_repo" config --local --add http.https://github.com/.extraheader "AUTHORIZATION: basic older-header"
echo 'change' >> "$fixture_repo/README.md"

cat > "$helper_dir/body.md" <<'BODYEOF'
fixture body
BODYEOF

mkdir -p "$helper_dir/bin"
real_git_path="$(command -v git)"
cat > "$helper_dir/bin/git" <<EOF
#!/usr/bin/env bash
real_git_path="$real_git_path"
for arg in "\$@"; do
  if [ "\$arg" = "fetch" ] || [ "\$arg" = "push" ]; then
    count="\${GIT_CONFIG_COUNT:-0}"
    i=0
    while [ "\$i" -lt "\$count" ]; do
      key_var="GIT_CONFIG_KEY_\$i"
      value_var="GIT_CONFIG_VALUE_\$i"
      printf '%s\t%s\t%s\n' "\$arg" "\${!key_var:-}" "\${!value_var:-}" >> "${auth_log}"
      i=\$((i + 1))
    done
    exit 0
  fi
done
exec "\$real_git_path" "\$@"
EOF
chmod +x "$helper_dir/bin/git"

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

(
  cd "$fixture_repo"
  PATH="$helper_dir/bin:$PATH" \
    GH_TOKEN="token-value" \
    GITHUB_REPOSITORY="example/repo" \
    GITHUB_REPOSITORY_OWNER="example" \
    GITHUB_OUTPUT="$pr_output" \
    bash "$ROOT_DIR/scripts/update/create_or_update_pr.sh" \
      "chore/auth-header-reset" \
      "main" \
      "chore: auth header reset fixture" \
      "chore: auth header reset fixture" \
      "$helper_dir/body.md"
)

expected_header="AUTHORIZATION: basic $(printf 'x-access-token:%s' "token-value" | base64 | tr -d '\n')"
if ! grep -Fxq "push	http.https://github.com/.extraheader	" "$auth_log"; then
  echo "create_or_update_pr did not reset inherited GitHub auth headers before push." >&2
  exit 1
fi

if ! grep -Fxq "push	http.https://github.com/.extraheader	$expected_header" "$auth_log"; then
  echo "create_or_update_pr did not pass the scoped GitHub auth header to push." >&2
  exit 1
fi

if git -C "$fixture_repo" config --local --get-all http.https://github.com/.extraheader | grep -Fq "$expected_header"; then
  echo "create_or_update_pr persisted the scoped GitHub auth header in local git config." >&2
  exit 1
fi

echo "create_or_update_pr auth header reset test passed."
