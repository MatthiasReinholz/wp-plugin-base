<?php
/**
 * Plugin Name: Ready Blocks
 * Description: Demonstrates WordPress readiness validation for packaged plugins.
 * Version: 1.3.0
 * Requires at least: 6.4
 * Requires PHP: 8.1
 * Author: Example Team
 * License: GPL-2.0-or-later
 * License URI: https://www.gnu.org/licenses/gpl-2.0.html
 * Text Domain: ready-blocks
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'READY_BLOCKS_VERSION', '1.3.0' );

require __DIR__ . '/includes/bootstrap.php';
