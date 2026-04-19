<?php
/**
 * Managed by wp-plugin-base. Do not edit manually.
 *
 * Legacy compatibility wrapper for the runtime updater bootstrap.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( file_exists( __DIR__ . '/wp-plugin-base-runtime-updater.php' ) ) {
	require_once __DIR__ . '/wp-plugin-base-runtime-updater.php';
}
