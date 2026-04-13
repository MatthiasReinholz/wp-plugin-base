<?php
/**
 * Plugin Name: Runtime Pack Ready
 * Version: 1.5.0
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'RUNTIME_PACK_READY_VERSION', '1.5.0' );

require __DIR__ . '/includes/bootstrap.php';
require_once __DIR__ . '/lib/wp-plugin-base/rest-operations/bootstrap.php';
require_once __DIR__ . '/lib/wp-plugin-base/admin-ui/bootstrap.php';
