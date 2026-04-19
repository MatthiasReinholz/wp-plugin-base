#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE_CONFIG="$ROOT_DIR/scripts/ci/validate_config.sh"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

cp -R "$ROOT_DIR/tests/fixtures/standard-plugin/." "$fixture/"
self_managed_api_base="https:"
self_managed_api_base="${self_managed_api_base}//gitlab.example.com/api/v4"
self_managed_issuer="https:"
self_managed_issuer="${self_managed_issuer}//auth.gitlab.example.com"
untrusted_api_base="https:"
untrusted_api_base="${untrusted_api_base}//releases.example.net/api/v4"
localhost_api_base="https:"
localhost_api_base="${localhost_api_base}//localhost/api/v4"
private_api_base="https:"
private_api_base="${private_api_base}//10.0.0.5/api/v4"
internal_api_base="https:"
internal_api_base="${internal_api_base}//mirror.internal/api/v4"

cat > "$fixture/.wp-plugin-base.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG

WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project >/dev/null

cat > "$fixture/.scope-sync.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
EOF_CONFIG
WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope sync .scope-sync.env >/dev/null

cat > "$fixture/.scope-foundation.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
EOF_CONFIG
WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope foundation .scope-foundation.env >/dev/null

cat > "$fixture/.scope-deploy-missing-slug.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope deploy .scope-deploy-missing-slug.env >/dev/null 2>&1; then
  echo "Deploy scope unexpectedly passed without WORDPRESS_ORG_SLUG." >&2
  exit 1
fi

cat > "$fixture/.scope-project-missing-name.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project .scope-project-missing-name.env >/dev/null 2>&1; then
  echo "Project scope unexpectedly passed without PLUGIN_NAME." >&2
  exit 1
fi

cat > "$fixture/.scope-project-invalid-name.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
PLUGIN_NAME=
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project .scope-project-invalid-name.env >/dev/null 2>&1; then
  echo "Project scope unexpectedly passed with an empty PLUGIN_NAME." >&2
  exit 1
fi

cat > "$fixture/.scope-project-invalid-codeowners.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
CODEOWNERS_REVIEWERS=example/platform
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project .scope-project-invalid-codeowners.env >/dev/null 2>&1; then
  echo "Project scope unexpectedly passed with invalid CODEOWNERS_REVIEWERS format." >&2
  exit 1
fi

cat > "$fixture/.scope-project-mixed-runtime-host.env" <<'EOF_CONFIG'
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
AUTOMATION_PROVIDER=github
PLUGIN_RUNTIME_UPDATE_PROVIDER=gitlab-release
PLUGIN_RUNTIME_UPDATE_SOURCE_URL=https://gitlab.com/example/standard-plugin
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project .scope-project-mixed-runtime-host.env >/dev/null 2>&1; then
  echo "Project scope unexpectedly passed with mixed downstream Git hosts." >&2
  exit 1
fi

cat > "$fixture/.scope-project-self-managed-gitlab-missing-issuer.env" <<EOF_CONFIG
FOUNDATION_RELEASE_SOURCE_PROVIDER=gitlab-release
FOUNDATION_RELEASE_SOURCE_REFERENCE=example-group/wp-plugin-base
FOUNDATION_RELEASE_SOURCE_API_BASE=${self_managed_api_base}
FOUNDATION_VERSION=v1.3.0
AUTOMATION_PROVIDER=gitlab
AUTOMATION_API_BASE=${self_managed_api_base}
TRUSTED_GIT_HOSTS=gitlab.example.com
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project .scope-project-self-managed-gitlab-missing-issuer.env >/dev/null 2>&1; then
  echo "Project scope unexpectedly passed for self-managed GitLab without FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER." >&2
  exit 1
fi

cat > "$fixture/.scope-project-untrusted-foundation-host.env" <<EOF_CONFIG
FOUNDATION_RELEASE_SOURCE_PROVIDER=gitlab-release
FOUNDATION_RELEASE_SOURCE_REFERENCE=example-group/wp-plugin-base
FOUNDATION_RELEASE_SOURCE_API_BASE=${untrusted_api_base}
FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER=https://gitlab.com
FOUNDATION_VERSION=v1.3.0
AUTOMATION_PROVIDER=gitlab
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project .scope-project-untrusted-foundation-host.env >/dev/null 2>&1; then
  echo "Project scope unexpectedly passed with an untrusted FOUNDATION_RELEASE_SOURCE_API_BASE host." >&2
  exit 1
fi

cat > "$fixture/.scope-project-untrusted-automation-host.env" <<EOF_CONFIG
FOUNDATION_REPOSITORY=MatthiasReinholz/wp-plugin-base
FOUNDATION_VERSION=v1.3.0
AUTOMATION_PROVIDER=gitlab
AUTOMATION_API_BASE=${untrusted_api_base}
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project .scope-project-untrusted-automation-host.env >/dev/null 2>&1; then
  echo "Project scope unexpectedly passed with an untrusted AUTOMATION_API_BASE host." >&2
  exit 1
fi

cat > "$fixture/.scope-project-localhost-trusted-host.env" <<EOF_CONFIG
FOUNDATION_RELEASE_SOURCE_PROVIDER=gitlab-release
FOUNDATION_RELEASE_SOURCE_REFERENCE=example-group/wp-plugin-base
FOUNDATION_RELEASE_SOURCE_API_BASE=${self_managed_api_base}
FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER=${self_managed_issuer}
FOUNDATION_VERSION=v1.3.0
AUTOMATION_PROVIDER=gitlab
AUTOMATION_API_BASE=${self_managed_api_base}
TRUSTED_GIT_HOSTS=gitlab.example.com,localhost
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project .scope-project-localhost-trusted-host.env >/dev/null 2>&1; then
  echo "Project scope unexpectedly passed with localhost in TRUSTED_GIT_HOSTS." >&2
  exit 1
fi

cat > "$fixture/.scope-project-private-trusted-host.env" <<EOF_CONFIG
FOUNDATION_RELEASE_SOURCE_PROVIDER=gitlab-release
FOUNDATION_RELEASE_SOURCE_REFERENCE=example-group/wp-plugin-base
FOUNDATION_RELEASE_SOURCE_API_BASE=${private_api_base}
FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER=${self_managed_issuer}
FOUNDATION_VERSION=v1.3.0
AUTOMATION_PROVIDER=gitlab
AUTOMATION_API_BASE=${private_api_base}
TRUSTED_GIT_HOSTS=10.0.0.5,auth.gitlab.example.com
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project .scope-project-private-trusted-host.env >/dev/null 2>&1; then
  echo "Project scope unexpectedly passed with a private-network host in TRUSTED_GIT_HOSTS." >&2
  exit 1
fi

cat > "$fixture/.scope-project-internal-trusted-host.env" <<EOF_CONFIG
FOUNDATION_RELEASE_SOURCE_PROVIDER=gitlab-release
FOUNDATION_RELEASE_SOURCE_REFERENCE=example-group/wp-plugin-base
FOUNDATION_RELEASE_SOURCE_API_BASE=${internal_api_base}
FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER=${self_managed_issuer}
FOUNDATION_VERSION=v1.3.0
AUTOMATION_PROVIDER=gitlab
AUTOMATION_API_BASE=${internal_api_base}
TRUSTED_GIT_HOSTS=mirror.internal,auth.gitlab.example.com
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project .scope-project-internal-trusted-host.env >/dev/null 2>&1; then
  echo "Project scope unexpectedly passed with an internal host in TRUSTED_GIT_HOSTS." >&2
  exit 1
fi

cat > "$fixture/.scope-project-self-managed-gitlab.env" <<EOF_CONFIG
FOUNDATION_RELEASE_SOURCE_PROVIDER=gitlab-release
FOUNDATION_RELEASE_SOURCE_REFERENCE=example-group/wp-plugin-base
FOUNDATION_RELEASE_SOURCE_API_BASE=${self_managed_api_base}
FOUNDATION_RELEASE_SOURCE_SIGSTORE_ISSUER=${self_managed_issuer}
FOUNDATION_VERSION=v1.3.0
AUTOMATION_PROVIDER=gitlab
AUTOMATION_API_BASE=${self_managed_api_base}
TRUSTED_GIT_HOSTS=gitlab.example.com,auth.gitlab.example.com
PLUGIN_NAME="Standard Plugin"
PLUGIN_SLUG=standard-plugin
MAIN_PLUGIN_FILE=standard-plugin.php
README_FILE=readme.txt
ZIP_FILE=standard-plugin.zip
PHP_VERSION=8.1
NODE_VERSION=20
EOF_CONFIG
WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope project .scope-project-self-managed-gitlab.env >/dev/null

if WP_PLUGIN_BASE_ROOT="$fixture" bash "$VALIDATE_CONFIG" --scope invalid .wp-plugin-base.env >/dev/null 2>&1; then
  echo "Config validation unexpectedly accepted an invalid scope." >&2
  exit 1
fi

echo "Config scope validation tests passed."
