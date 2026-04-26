<?php
/**
 * Managed bootstrap for the admin UI pack.
 *
 * @package WPPluginBase
 * @since NEXT
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if (
	function_exists( 'is_admin' )
	&& ! is_admin()
	&& ! ( defined( 'WP_CLI' ) && WP_CLI )
) {
	return;
}

require_once __DIR__ . '/class-wp-plugin-base-admin-ui-loader.php';

$wp_plugin_base_admin_ui_bootstrap = dirname( __DIR__, 3 ) . '/includes/admin-ui/bootstrap.php';
if ( file_exists( $wp_plugin_base_admin_ui_bootstrap ) ) {
	require_once $wp_plugin_base_admin_ui_bootstrap;
}
