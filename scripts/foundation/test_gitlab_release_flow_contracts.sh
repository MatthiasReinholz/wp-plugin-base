#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

fixture="$(mktemp -d)"
origin_repo="$(mktemp -d)"
captured_body="$(mktemp)"

cleanup() {
  rm -rf "$fixture" "$origin_repo" "$captured_body"
}
trap cleanup EXIT

cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$fixture/"
mkdir -p "$fixture/.wp-plugin-base"
rsync -a --exclude '.git' "$ROOT_DIR/" "$fixture/.wp-plugin-base/"

cat > "$fixture/.wp-plugin-base.env" <<'EOF'
FOUNDATION_RELEASE_SOURCE_PROVIDER=gitlab-release
FOUNDATION_RELEASE_SOURCE_REFERENCE=example-group/wp-plugin-base
FOUNDATION_RELEASE_SOURCE_API_BASE=https://gitlab.com/api/v4
FOUNDATION_VERSION=v1.5.0
AUTOMATION_PROVIDER=gitlab
AUTOMATION_API_BASE=https://gitlab.com/api/v4
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=22
PRODUCTION_ENVIRONMENT=production
CODEOWNERS_REVIEWERS=@example/platform
EOF

(
  cd "$fixture"
  git init >/dev/null
  git branch -M main >/dev/null
  git config user.name tester
  git config user.email tester@example.invalid
  git add .
  git commit -m "Initial commit" >/dev/null
  git init --bare "$origin_repo/origin.git" >/dev/null
  git remote add origin "$origin_repo/origin.git"
  git push -u origin main >/dev/null
)

missing_tag_log="$(mktemp)"
if (
  cd "$fixture"
  WP_PLUGIN_BASE_ROOT="$fixture" CI_PROJECT_PATH=example-group/standard-plugin \
    bash "$ROOT_DIR/scripts/release/run_gitlab_release.sh" "9.9.9" ".wp-plugin-base.env"
) >"$missing_tag_log" 2>&1; then
  echo "run_gitlab_release unexpectedly passed without an existing tag." >&2
  exit 1
fi
grep -Fq 'requires an existing tag' "$missing_tag_log"
rm -f "$missing_tag_log"

cat > "$fixture/.wp-plugin-base/scripts/update/create_or_update_change_request.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cp "$5" "$WP_PLUGIN_BASE_CAPTURED_BODY"
EOF
chmod +x "$fixture/.wp-plugin-base/scripts/update/create_or_update_change_request.sh"

(
  cd "$fixture"
  WP_PLUGIN_BASE_ROOT="$fixture" \
    AUTOMATION_PROJECT_PATH=example-group/standard-plugin \
    WP_PLUGIN_BASE_CAPTURED_BODY="$captured_body" \
    bash "$fixture/.wp-plugin-base/scripts/release/prepare_release_change_request.sh" patch "" main ".wp-plugin-base.env" >/dev/null
)

grep -Fq 'create and push the release tag manually after merge' "$captured_body"
grep -Fq 'git tag ' "$captured_body"
grep -Fq 'git push origin ' "$captured_body"

release_body="$(mktemp)"
(
  cd "$fixture"
  WP_PLUGIN_BASE_ROOT="$fixture" \
    bash "$ROOT_DIR/scripts/release/generate_github_release_body.sh" "1.2.3" ".wp-plugin-base.env" >"$release_body"
)
grep -Fq 'GitLab also provides automatic source code archives' "$release_body"
if grep -Fq 'GitHub also provides automatic source code archives' "$release_body"; then
  echo "GitLab release body unexpectedly used GitHub-specific source archive text." >&2
  exit 1
fi
rm -f "$release_body"

# Execute the orchestrator with isolated host adapters. This tests the state
# transitions and ordering, rather than only searching the workflow text.
log_file="$fixture/release-events"
export WP_PLUGIN_BASE_RELEASE_EVENTS="$log_file"
for script in ci/check_release_pr ci/check_versions ci/lint_php ci/lint_js \
  ci/validate_wordpress_readiness release/generate_github_release_body \
  release/install_release_security_tools release/generate_sbom release/sign_release \
  release/verify_sigstore_bundle release/validate_wordpress_org_deploy \
  release/validate_woocommerce_com_deploy release/publish_gitlab_release \
  release/deploy_wordpress_org release/deploy_woocommerce_com; do
  cat > "$fixture/.wp-plugin-base/scripts/$script.sh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${0##*/}" >> "$WP_PLUGIN_BASE_RELEASE_EVENTS"
MOCK
done
cp "$fixture/.wp-plugin-base/scripts/ci/build_zip.sh" "$fixture/.wp-plugin-base/scripts/ci/build_zip.real.sh"
cat > "$fixture/.wp-plugin-base/scripts/ci/build_zip.sh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' build_zip.sh >> "$WP_PLUGIN_BASE_RELEASE_EVENTS"
exec bash "$WP_PLUGIN_BASE_ROOT/.wp-plugin-base/scripts/ci/build_zip.real.sh" "$@"
MOCK
cat > "$fixture/.wp-plugin-base/scripts/release/restore_gitlab_release_assets.sh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' restore_gitlab_release_assets.sh >> "$WP_PLUGIN_BASE_RELEASE_EVENTS"
if [ "${WP_PLUGIN_BASE_FIXTURE_RESTORE_STATUS:-3}" = 0 ]; then
  python3 - "$WP_PLUGIN_BASE_ROOT/dist/package-generation.json" "$WP_PLUGIN_BASE_PACKAGE_RESULT_FILE" <<'PYTHON'
import json, pathlib, sys
record = json.loads(pathlib.Path(sys.argv[1]).read_text())
with pathlib.Path(sys.argv[2]).open('a') as stream:
    for key in ('package_dir', 'zip_path', 'sbom_path', 'signature_path', 'descriptor_path', 'sha256'):
        stream.write(f'{key}={record[key]}\n')
PYTHON
fi
exit "${WP_PLUGIN_BASE_FIXTURE_RESTORE_STATUS:-3}"
MOCK
(
  cd "$fixture"
  git checkout -q main
  git tag -a 1.2.3 -m 'Release 1.2.3'
  git push -q origin 1.2.3
)
mkdir -p "$fixture/orchestrator-bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture/orchestrator-bin/svn"
chmod +x "$fixture/orchestrator-bin/svn"
run_release_fixture() {
  : > "$log_file"
  (
    cd "$fixture"
    PATH="$fixture/orchestrator-bin:$PATH" WP_PLUGIN_BASE_ROOT="$fixture" CI_PROJECT_PATH=example-group/standard-plugin \
      SIGSTORE_ID_TOKEN=fixture-oidc-token WP_ORG_DEPLOY_ENABLED=true \
      WOOCOMMERCE_COM_DEPLOY_ENABLED=true WOOCOMMERCE_COM_PRODUCT_ID=12345 \
      WP_PLUGIN_BASE_FIXTURE_RESTORE_STATUS="$1" \
      bash "$fixture/.wp-plugin-base/scripts/release/run_gitlab_release.sh" 1.2.3 .wp-plugin-base.env
  )
}
run_release_fixture 3
publish_line="$(grep -n '^publish_gitlab_release.sh$' "$log_file" | cut -d: -f1)"
for channel in deploy_wordpress_org.sh deploy_woocommerce_com.sh; do
  channel_line="$(grep -n "^$channel\$" "$log_file" | cut -d: -f1)"
  test "$channel_line" -gt "$publish_line"
done
run_release_fixture 0
if grep -Eq '^(build_zip|publish_gitlab_release|sign_release)\.sh$' "$log_file"; then
  echo "Channel retry unexpectedly rebuilt or republished immutable assets." >&2
  exit 1
fi
grep -Fq deploy_wordpress_org.sh "$log_file"
grep -Fq deploy_woocommerce_com.sh "$log_file"
if run_release_fixture 1; then
  echo "Release recovery continued after artifact verification failed." >&2
  exit 1
fi
if grep -Eq '^deploy_' "$log_file"; then
  echo "Release recovery deployed unverified artifacts." >&2
  exit 1
fi

# Model the GitLab REST contract, ensuring uploaded assets exist before the
# initial release is public and credentials never appear in process arguments.
mkdir -p "$fixture/publish-bin"
cat > "$fixture/publish-bin/curl" <<'MOCK'
#!/usr/bin/env python3
import json
import os
import pathlib
import sys

args = sys.argv[1:]
assert 'fixture-private-token' not in ' '.join(args), 'Token leaked into curl arguments'
headers = [args[i + 1] for i, arg in enumerate(args[:-1]) if arg == '--header']
assert any(h.startswith('@') and pathlib.Path(h[1:]).read_text() == 'PRIVATE-TOKEN: fixture-private-token\n' for h in headers)
method = args[args.index('--request') + 1]
url = args[-1]
with open(os.environ['WP_PLUGIN_BASE_RELEASE_EVENTS'], 'a') as log:
    log.write(method + ' ' + url + '\n')
if '--write-out' in args:
    destination = args[args.index('--output') + 1]
    pathlib.Path(destination).write_text('{}')
    print('404')
elif '/releases?' in url:
    print(json.dumps([{'tag_name': '1.3.0'}] if os.getenv('MOCK_NEWER_RELEASE') == 'true' else []))
elif url.endswith('/uploads'):
    if os.getenv('MOCK_UPLOAD_FAILURE') == 'true':
        sys.exit(22)
    print(json.dumps({'full_path': '/example-group/standard-plugin/uploads/digest/asset.txt'}))
elif method == 'POST' and url.endswith('/releases'):
    body = json.loads(args[args.index('--data') + 1])
    assert len(body['assets']['links']) == 1
    print('{}')
else:
    raise SystemExit('Unexpected REST call: ' + method + ' ' + url)
MOCK
chmod +x "$fixture/publish-bin/curl"
printf 'release notes\n' > "$fixture/notes.md"
printf 'asset\n' > "$fixture/asset.txt"
publish_fixture() {
  : > "$log_file"
  PATH="$fixture/publish-bin:$PATH" GITLAB_TOKEN=fixture-private-token \
    CI_PROJECT_PATH=example-group/standard-plugin \
    bash "$ROOT_DIR/scripts/release/publish_gitlab_release.sh" \
      1.2.3 1.2.3 "$fixture/notes.md" "$fixture/asset.txt"
}
publish_fixture
upload_line="$(grep -n '/uploads$' "$log_file" | cut -d: -f1)"
release_line="$(grep -n 'POST .*/releases$' "$log_file" | cut -d: -f1)"
test "$upload_line" -lt "$release_line"
if MOCK_UPLOAD_FAILURE=true publish_fixture; then
  echo "GitLab release publication succeeded after an asset upload failed." >&2
  exit 1
fi
if grep -q 'POST .*/releases$' "$log_file"; then
  echo "GitLab published an incomplete release after upload failure." >&2
  exit 1
fi
if MOCK_NEWER_RELEASE=true publish_fixture; then
  echo "GitLab accepted historical first publication after a newer version." >&2
  exit 1
fi
if grep -q 'POST ' "$log_file"; then
  echo "GitLab wrote release state after the version-order guard failed." >&2
  exit 1
fi

echo "GitLab release flow contract tests passed."
