<?php
/**
 * Managed bootstrap for the REST operations pack.
 *
 * @package WPPluginBase
 * @since NEXT
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

require_once __DIR__ . '/class-wp-plugin-base-rest-operations-registry.php';
require_once __DIR__ . '/class-wp-plugin-base-rest-operations-input.php';
require_once __DIR__ . '/class-wp-plugin-base-rest-operations-permissions.php';
require_once __DIR__ . '/class-wp-plugin-base-rest-operations-responses.php';
require_once __DIR__ . '/class-wp-plugin-base-rest-operations-executor.php';
require_once __DIR__ . '/class-wp-plugin-base-rest-operations-rest-adapter.php';
require_once __DIR__ . '/class-wp-plugin-base-rest-operations-abilities-adapter.php';

$wp_plugin_base_rest_operations_bootstrap = dirname( __DIR__, 3 ) . '/includes/rest-operations/bootstrap.php';

if ( file_exists( $wp_plugin_base_rest_operations_bootstrap ) ) {
	$operations = require $wp_plugin_base_rest_operations_bootstrap;
	if ( is_array( $operations ) ) {
		WP_Plugin_Base_REST_Operations_Registry::register_many( $operations );
	}
}

add_action(
	'rest_api_init',
	static function () {
		WP_Plugin_Base_REST_Operations_REST_Adapter::register_all(
			'__PLUGIN_SLUG__',
			'__REST_API_NAMESPACE__',
			WP_Plugin_Base_REST_Operations_Registry::all()
		);
	}
);

if ( 'true' === '__REST_ABILITIES_ENABLED__' ) {
	add_action(
		'wp_abilities_api_categories_init',
		static function () {
			WP_Plugin_Base_REST_Operations_Abilities_Adapter::register_category(
				'__PLUGIN_SLUG__',
				'__PLUGIN_NAME__'
			);
		}
	);

	add_action(
		'wp_abilities_api_init',
		static function () {
			WP_Plugin_Base_REST_Operations_Abilities_Adapter::register_operations(
				'__PLUGIN_SLUG__',
				'__PLUGIN_SLUG__',
				WP_Plugin_Base_REST_Operations_Registry::all()
			);
		}
	);
}
