<?php
/**
 * Plugin Name: Build Ready Plugin
 * Description: Demonstrates packaging for a plugin that ships generated @wordpress/build artifacts.
 * Version: 1.4.0
 * Requires at least: 6.4
 * Requires PHP: 8.1
 * Author: Example Team
 * License: GPL-2.0-or-later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: build-ready-plugin
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'BUILD_READY_PLUGIN_VERSION', '1.4.0' );

require __DIR__ . '/build/build.php';
