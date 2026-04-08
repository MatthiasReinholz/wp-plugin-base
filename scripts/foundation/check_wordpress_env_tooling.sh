#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"
TOOLS_DIR="$ROOT_DIR/tools/wordpress-env"
PACKAGE_JSON="$TOOLS_DIR/package.json"
PACKAGE_LOCK="$TOOLS_DIR/package-lock.json"
NPMRC="$TOOLS_DIR/.npmrc"
INSTALL_DIR="$(mktemp -d)"
CACHE_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$INSTALL_DIR" "$CACHE_DIR"
}

trap cleanup EXIT

wp_plugin_base_require_commands "wordpress-env tooling checks" node npm

for path in "$PACKAGE_JSON" "$PACKAGE_LOCK" "$NPMRC"; do
  if [ ! -f "$path" ]; then
    echo "Missing required wordpress-env tooling file: $path" >&2
    exit 1
  fi
done

grep -Fxq 'engine-strict=true' "$NPMRC" || {
  echo "tools/wordpress-env/.npmrc must contain engine-strict=true" >&2
  exit 1
}

node - <<'EOF' "$PACKAGE_JSON" "$PACKAGE_LOCK"
const fs = require("node:fs");

const [packageJsonPath, packageLockPath] = process.argv.slice(2);
const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
const packageLock = JSON.parse(fs.readFileSync(packageLockPath, "utf8"));
const expectedVersion = packageJson.devDependencies?.["@wordpress/env"];
const lockRoot = packageLock.packages?.[""] ?? {};
const lockPackage = packageLock.packages?.["node_modules/@wordpress/env"] ?? {};

if (!expectedVersion) {
  throw new Error("tools/wordpress-env/package.json must declare @wordpress/env");
}

if (lockRoot.devDependencies?.["@wordpress/env"] !== expectedVersion) {
  throw new Error("package-lock root entry for @wordpress/env does not match package.json");
}

if (lockPackage.version !== expectedVersion) {
  throw new Error("resolved @wordpress/env version in package-lock does not match package.json");
}
EOF

if ! grep -Fq '"$source_dir/.npmrc"' "$ROOT_DIR/scripts/lib/wordpress_tooling.sh"; then
  echo "scripts/lib/wordpress_tooling.sh must copy tools/wordpress-env/.npmrc into the temp install dir" >&2
  exit 1
fi

cp "$NPMRC" "$PACKAGE_JSON" "$PACKAGE_LOCK" "$INSTALL_DIR/"
(
  cd "$INSTALL_DIR"
  NPM_CONFIG_CACHE="$CACHE_DIR" npm ci --no-audit --no-fund >/dev/null
  NPM_CONFIG_CACHE="$CACHE_DIR" npm audit signatures >/dev/null
)

echo "wordpress-env tooling policy checks passed."
