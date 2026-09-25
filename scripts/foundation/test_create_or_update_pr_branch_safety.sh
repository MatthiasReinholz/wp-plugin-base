#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

fixture_repo="$(mktemp -d)"
fixture_origin="$(mktemp -d)"
helper_dir="$(mktemp -d)"
pr_output="$(mktemp)"

cleanup() {
  rm -rf "$fixture_repo" "$fixture_origin" "$helper_dir" "$pr_output"
}
trap cleanup EXIT

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

git -C "$fixture_repo" checkout -qb chore/existing-branch
printf '%s\n' 'branch-only-marker' > "$fixture_repo/BRANCH_ONLY.txt"
git -C "$fixture_repo" add BRANCH_ONLY.txt
git -C "$fixture_repo" commit -qm "branch-only commit"

git -C "$fixture_repo" checkout -q main

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

(
  cd "$fixture_repo"
  PATH="$helper_dir/bin:$PATH" \
    GITHUB_REPOSITORY="example/repo" \
    GITHUB_REPOSITORY_OWNER="example" \
    GITHUB_OUTPUT="$pr_output" \
    bash "$ROOT_DIR/scripts/update/create_or_update_pr.sh" \
      "chore/existing-branch" \
      "main" \
      "chore: branch safety fixture" \
      "chore: branch safety fixture" \
      "$helper_dir/body.md"
)

if ! git -C "$fixture_repo" cat-file -e HEAD:BRANCH_ONLY.txt >/dev/null 2>&1; then
  echo "create_or_update_pr unexpectedly reset the existing branch and dropped branch-only content." >&2
  exit 1
fi

if ! grep -Fxq 'pull_request_operation=none' "$pr_output"; then
  echo "Expected no PR operation when no changes were staged." >&2
  exit 1
fi

echo "create_or_update_pr branch safety test passed."

# A fresh fetch must not authorize replacing reviewer commits with a stale local
# updater branch. Exercise the actual bare-remote rejection, without mocking Git.
git -C "$fixture_repo" checkout -q main
git -C "$fixture_repo" checkout -qb chore/diverged-branch
printf '%s\n' 'original update' > "$fixture_repo/UPDATE.txt"
git -C "$fixture_repo" add UPDATE.txt
git -C "$fixture_repo" commit -qm "original update"
git -C "$fixture_repo" push -q origin chore/diverged-branch
reviewer_repo="$helper_dir/reviewer"
git clone -q --branch chore/diverged-branch "$fixture_origin" "$reviewer_repo"
git -C "$reviewer_repo" config user.email "reviewer@example.com"
git -C "$reviewer_repo" config user.name "Reviewer"
printf '%s\n' 'preserve reviewer work' > "$reviewer_repo/REVIEWER.txt"
git -C "$reviewer_repo" add REVIEWER.txt
git -C "$reviewer_repo" commit -qm "reviewer improvement"
git -C "$reviewer_repo" push -q origin chore/diverged-branch
remote_before="$(git -C "$fixture_origin" rev-parse refs/heads/chore/diverged-branch)"
git -C "$fixture_repo" checkout -q main
printf '%s\n' 'refreshed candidate' >> "$fixture_repo/README.md"
: > "$pr_output"

if (
  cd "$fixture_repo"
  PATH="$helper_dir/bin:$PATH" \
    GH_TOKEN='' GITHUB_TOKEN='' \
    GITHUB_REPOSITORY="example/repo" \
    GITHUB_REPOSITORY_OWNER="example" \
    GITHUB_OUTPUT="$pr_output" \
    GIT_ADD_PATHS='README.md' \
    bash "$ROOT_DIR/scripts/update/create_or_update_pr.sh" \
      "chore/diverged-branch" "main" \
      "chore: refreshed candidate" "chore: refreshed candidate" \
      "$helper_dir/body.md"
) > "$helper_dir/diverged.log" 2>&1; then
  echo "create_or_update_pr unexpectedly replaced newer remote reviewer commits." >&2
  exit 1
fi

remote_after="$(git -C "$fixture_origin" rev-parse refs/heads/chore/diverged-branch)"
if [ "$remote_before" != "$remote_after" ]; then
  echo "A rejected change-request refresh changed the remote branch." >&2
  exit 1
fi
git -C "$fixture_origin" cat-file -e refs/heads/chore/diverged-branch:REVIEWER.txt
grep -Fq 'Reconcile any remote branch changes before retrying' "$helper_dir/diverged.log"
if [ -s "$pr_output" ]; then
  echo "A rejected branch publication unexpectedly reported a change-request operation." >&2
  exit 1
fi

echo "create_or_update_pr preserves remote reviewer commits on divergence."
