#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$fixture/"
mkdir -p "$fixture/.wp-plugin-base"
rsync -a --exclude .git "$ROOT_DIR/" "$fixture/.wp-plugin-base/"
printf '\nBUILD_SCRIPT=noop-build.sh\n' >> "$fixture/.wp-plugin-base.env"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture/noop-build.sh"
WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh" >/dev/null

# Every enabled managed class and required child bootstrap must survive custom
# package selection. Documentation and build-tool seeds remain excluded.
WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh" >/dev/null
unzip -Z1 "$fixture/dist/runtime-pack-ready.zip" > "$fixture/zip-list"
grep -Fxq 'runtime-pack-ready/lib/wp-plugin-base/admin-ui/class-wp-plugin-base-admin-ui-loader.php' "$fixture/zip-list"
if grep -Eq '^runtime-pack-ready/(docs|\.wp-plugin-base-admin-ui)/' "$fixture/zip-list"; then
  echo 'Runtime package included documentation or build tooling.' >&2
  exit 1
fi
for excluded in \
  lib/wp-plugin-base/rest-operations/class-wp-plugin-base-rest-operations-input.php \
  lib/wp-plugin-base/admin-ui/class-wp-plugin-base-admin-ui-loader.php \
  includes/rest-operations/bootstrap.php \
  includes/admin-ui/bootstrap.php
do
  printf '\nPACKAGE_EXCLUDE=%s\n' "$excluded" >> "$fixture/.wp-plugin-base.env"
  if WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh" > "$fixture/package.log" 2>&1; then
    echo "Runtime package accepted missing PHP: $excluded" >&2
    exit 1
  fi
  grep -Fq "$excluded" "$fixture/package.log"
done
printf '\nPACKAGE_EXCLUDE=\nPACKAGE_INCLUDE=runtime-pack-ready.php,readme.txt,includes\n' >> "$fixture/.wp-plugin-base.env"
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/build_zip.sh" > "$fixture/package.log" 2>&1; then
  echo 'Custom includes dropped enabled managed runtime PHP.' >&2
  exit 1
fi
grep -Fq 'missing required PHP in the package' "$fixture/package.log"

# Both adapters consume the same lexical import resolver.
for import in \
  'use function register_rest_route as endpoint;' \
  'use function \register_rest_route as ENDPOINT;' \
  'use function \strlen as length, \register_rest_route as endpoint;'
do
  printf "<?php\nnamespace Fixture;\n%s\nendpoint( 'fixture/v1', '/open', array( 'callback' => '__return_true', 'permission_callback' => '__return_true' ) );\n" "$import" > "$fixture/alias-route.php"
  php -l "$fixture/alias-route.php" >/dev/null
  php "$ROOT_DIR/scripts/ci/php_wordpress_authorization_scanner.php" "$fixture/alias-route.php" > "$fixture/authorization.log"
  grep -Fq rest_permission_callback_true "$fixture/authorization.log"
  if WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/scan_rest_operation_contract.sh" > "$fixture/contract.log" 2>&1; then
    echo 'Registry scanner accepted an aliased direct route registration.' >&2
    exit 1
  fi
  grep -Fq alias-route.php "$fixture/contract.log"
done

# Imports apply lexically forward; an earlier call does not gain a later alias.
cat > "$fixture/alias-route.php" <<'PHP'
<?php
namespace Earlier;
endpoint('fixture/v1', '/early', array('permission_callback' => '__return_true'));
use function \register_rest_route as endpoint;
PHP
php "$ROOT_DIR/scripts/ci/php_wordpress_authorization_scanner.php" "$fixture/alias-route.php" > "$fixture/authorization.log"
test ! -s "$fixture/authorization.log"
WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/scan_rest_operation_contract.sh" >/dev/null

# Grouped imports resolve to their declared namespace; namespace boundaries and
# object methods must never inherit a global function alias accidentally.
cat > "$fixture/alias-route.php" <<'PHP'
<?php
namespace First {
    use function \Vendor\{register_rest_route as endpoint, strlen};
    use Vendor\{Thing, function register_rest_route as other_endpoint};
    endpoint('fixture/v1', '/namespaced', array());
    other_endpoint('fixture/v1', '/mixed', array());
    use function \register_rest_route as route;
    $client->route('fixture/v1', '/method', array());
    Client::route('fixture/v1', '/static-method', array());
    class Example {
        public function &route() { static $value; return $value; }
    }
    $closure = function () use ($route) {};
}
namespace Second {
    function route() {}
    route('fixture/v1', '/unrelated', array());
}
PHP
php -l "$fixture/alias-route.php" >/dev/null
php "$ROOT_DIR/scripts/ci/php_wordpress_authorization_scanner.php" "$fixture/alias-route.php" > "$fixture/authorization.log"
test ! -s "$fixture/authorization.log"
WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/scan_rest_operation_contract.sh" >/dev/null
TOKEN_HELPERS="$ROOT_DIR/scripts/lib/php_tokens.php" php <<'PHP'
<?php
require getenv('TOKEN_HELPERS');
foreach (array(
    'function Vendor\{register_rest_route as route, strlen}' => array('route' => 'Vendor\register_rest_route', 'strlen' => 'Vendor\strlen'),
    'Vendor\{Thing, function register_rest_route as route}' => array('route' => 'Vendor\register_rest_route'),
) as $declaration => $expected) {
    if (wp_plugin_base_parse_function_imports($declaration) !== $expected) {
        throw new RuntimeException('Grouped function imports were not resolved exactly.');
    }
}
PHP
echo 'Runtime package closure and lexical function alias contracts passed.'
