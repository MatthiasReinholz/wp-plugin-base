<?php
/**
 * Plugin Name: Existing Application
 * Version: 1.0.0
 * Requires at least: 7.1
 * Requires PHP: 8.1
 * Text Domain: existing-application
 * License: GPL-3.0-or-later
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}
define( 'EXISTING_APPLICATION_VERSION', '1.0.0' );

add_action( 'admin_menu', static function () {
	$hook = add_management_page( 'Existing Application', 'Existing Application', 'manage_options', 'existing-application', static function () {
		echo '<div id="existing-application-root"></div>';
	} );
	add_action( 'admin_enqueue_scripts', static function ( $current_hook ) use ( $hook ) {
		if ( $hook !== $current_hook ) {
			return;
		}
		$asset = require __DIR__ . '/build/index.asset.php';
		wp_enqueue_script( 'existing-application', plugins_url( 'build/index.js', __FILE__ ), $asset['dependencies'], $asset['version'], true );
		wp_enqueue_style( 'existing-application', plugins_url( 'build/index.css', __FILE__ ), array( 'wp-components' ), $asset['version'] );
		wp_style_add_data( 'existing-application', 'rtl', 'replace' );
	} );
} );
