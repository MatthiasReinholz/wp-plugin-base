#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOADER_PATH="$ROOT_DIR/templates/child/admin-ui-pack/lib/wp-plugin-base/admin-ui/class-wp-plugin-base-admin-ui-loader.php"

WP_PLUGIN_BASE_ADMIN_UI_LOADER_PATH="$LOADER_PATH" php <<'PHP'
<?php
define( 'ABSPATH', __DIR__ );

function esc_attr( $value ) {
    return htmlspecialchars( (string) $value, ENT_QUOTES, 'UTF-8' );
}

require getenv( 'WP_PLUGIN_BASE_ADMIN_UI_LOADER_PATH' );

$method = new ReflectionMethod( 'WP_Plugin_Base_Admin_UI_Loader', 'render_root' );
if ( PHP_VERSION_ID < 80100 ) {
    $method->setAccessible( true );
}

ob_start();
$method->invoke(
    null,
    array(
        'root_id' => 'fixture-admin-ui-root',
    )
);
$markup = ob_get_clean();

$header_end_position = strpos( $markup, 'class="wp-header-end"' );
$root_position       = strpos( $markup, 'fixture-admin-ui-root' );

if ( false === $header_end_position ) {
    fwrite( STDERR, 'Expected admin UI loader shell to include the WordPress wp-header-end marker.' . PHP_EOL );
    exit( 1 );
}

if ( false === $root_position ) {
    fwrite( STDERR, 'Expected admin UI loader shell to include the React root element.' . PHP_EOL );
    exit( 1 );
}

if ( $header_end_position > $root_position ) {
    fwrite( STDERR, 'Expected admin UI loader shell to emit wp-header-end before the React root.' . PHP_EOL );
    exit( 1 );
}

echo 'Admin UI loader shell tests passed.' . PHP_EOL;
PHP
