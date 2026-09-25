#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Protect the regression itself when invoked directly from a Git hook context.
repository_environment="$(git rev-parse --local-env-vars)"
while IFS= read -r variable; do
  unset "$variable"
done <<< "$repository_environment"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
owner="$fixture/owner"
origin="$fixture/origin.git"
mkdir -p "$owner/.githooks" "$owner/scripts/foundation"
cp "$ROOT_DIR/.githooks/pre-push" "$owner/.githooks/pre-push"
chmod +x "$owner/.githooks/pre-push"

# The real push invokes our copied hook. Its validators exercise the same Git
# init/config/branch/add/commit operations that must never affect the owner.
cat > "$owner/scripts/foundation/validate.sh" <<'VALIDATOR'
#!/usr/bin/env bash
set -euo pipefail
repository_environment="$(git rev-parse --local-env-vars)"
while IFS= read -r variable; do
  if [ "${!variable+x}" = x ]; then
    echo "Repository-local Git variable leaked into validation: $variable" >&2
    exit 1
  fi
done <<< "$repository_environment"
if [ "${WP_PLUGIN_BASE_ISOLATION_SENTINEL:-}" != 'preserve general environment' ]; then
  echo 'Hook discarded unrelated environment.' >&2
  exit 1
fi
child="$WP_PLUGIN_BASE_ISOLATION_FIXTURE/child-$WP_PLUGIN_BASE_ISOLATION_RUN-$(basename "$0")"
mkdir -p "$child"
git -C "$child" init -q
git -C "$child" branch -M fixture-branch
git -C "$child" config user.name 'Fixture User'
git -C "$child" config user.email fixture@example.invalid
printf '%s\n' 'child content' > "$child/fixture.txt"
git -C "$child" add fixture.txt
git -C "$child" commit -qm 'Fixture initial commit'
test "$(git -C "$child" branch --show-current)" = fixture-branch
test "$(git -C "$child" ls-tree --name-only HEAD)" = fixture.txt
printf '%s\n' "$(basename "$0") $*" >> "$WP_PLUGIN_BASE_ISOLATION_FIXTURE/calls"
VALIDATOR
cp "$owner/scripts/foundation/validate.sh" "$owner/scripts/foundation/validate-full.sh"
git -C "$owner" init -q
git -C "$owner" branch -M owner-branch
git -C "$owner" config user.name 'Owner User'
git -C "$owner" config user.email owner@example.invalid
git -C "$owner" config core.hooksPath .githooks
git init --bare -q "$origin"
git -C "$owner" remote add origin "$origin"
printf '%s\n' 'committed content' > "$owner/owned.txt"
git -C "$owner" add .
git -C "$owner" commit -qm 'Owner commit'
printf '%s\n' 'unstaged user work' >> "$owner/owned.txt"
printf '%s\n' 'staged user work' > "$owner/staged.txt"
git -C "$owner" add staged.txt
printf '%s\n' 'untracked user work' > "$owner/untracked.txt"
linked="$fixture/linked"
git -C "$owner" worktree add -qb linked-branch "$linked"
printf '%s\n' 'linked worktree user change' >> "$linked/owned.txt"
linked_git_dir="$(git -C "$linked" rev-parse --absolute-git-dir)"
linked_head="$(git -C "$linked" rev-parse HEAD)"
git -C "$linked" status --porcelain=v1 > "$fixture/linked-status"
cp "$linked_git_dir/index" "$fixture/linked-index"
owner_head="$(git -C "$owner" rev-parse HEAD)"
cp "$owner/.git/config" "$fixture/owner-config"
git -C "$owner" status --porcelain=v1 > "$fixture/owner-status"
cp "$owner/.git/index" "$fixture/owner-index"

export WP_PLUGIN_BASE_ISOLATION_FIXTURE="$fixture"
export WP_PLUGIN_BASE_ISOLATION_SENTINEL='preserve general environment'
export WP_PLUGIN_BASE_ISOLATION_RUN=real-push
# Do not inherit a developer's optional local bypass: this test must run the hook.
unset WP_PLUGIN_BASE_SKIP_LOCAL_PUSH_GATE
git -C "$owner" push -q origin owner-branch

# Also exercise the full local-path environment a caller/worktree can export.
WP_PLUGIN_BASE_ISOLATION_RUN=explicit-environment \
  GIT_DIR="$owner/.git" GIT_WORK_TREE="$owner" GIT_COMMON_DIR="$owner/.git" GIT_INDEX_FILE="$owner/.git/index" \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0='Injected User' \
  bash "$owner/.githooks/pre-push"

WP_PLUGIN_BASE_ISOLATION_RUN=linked-worktree \
  GIT_DIR="$linked_git_dir" GIT_WORK_TREE="$linked" GIT_COMMON_DIR="$owner/.git" GIT_INDEX_FILE="$linked_git_dir/index" \
  bash "$linked/.githooks/pre-push"

test "$(git -C "$linked" rev-parse HEAD)" = "$linked_head"
test "$(git -C "$linked" branch --show-current)" = linked-branch
cmp "$fixture/linked-index" "$linked_git_dir/index"
git -C "$linked" status --porcelain=v1 > "$fixture/linked-after-status"
cmp "$fixture/linked-status" "$fixture/linked-after-status"
test "$(git -C "$owner" rev-parse HEAD)" = "$owner_head"
test "$(git -C "$owner" branch --show-current)" = owner-branch
cmp "$fixture/owner-config" "$owner/.git/config"
cmp "$fixture/owner-index" "$owner/.git/index"
git -C "$owner" status --porcelain=v1 > "$fixture/after-status"
cmp "$fixture/owner-status" "$fixture/after-status"
cat > "$fixture/expected-calls" <<'CALLS'
validate.sh --mode fast-local
validate-full.sh --mode fast-local
validate.sh --mode fast-local
validate-full.sh --mode fast-local
validate.sh --mode fast-local
validate-full.sh --mode fast-local
CALLS
cmp "$fixture/expected-calls" "$fixture/calls"
echo 'Pre-push Git repository isolation tests passed.'
