<?php
/**
 * Child-owned REST operations bootstrap.
 *
 * @package __PLUGIN_SLUG__
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

$wp_plugin_base_attach_operation_source = static function ( $source_file, $operations ) {
	if ( ! is_array( $operations ) ) {
		return array();
	}

	return array_map(
		static function ( $operation ) use ( $source_file ) {
			if ( ! is_array( $operation ) ) {
				return $operation;
			}

			if ( empty( $operation['source_file'] ) ) {
				$operation['source_file'] = $source_file;
			}

			return $operation;
		},
		$operations
	);
};

$settings_operations = $wp_plugin_base_attach_operation_source(
	'includes/rest-operations/settings-operations.php',
	require __DIR__ . '/settings-operations.php'
);
$example_items_operations = $wp_plugin_base_attach_operation_source(
	'includes/rest-operations/example-items-operations.php',
	require __DIR__ . '/example-items-operations.php'
);

return array_merge(
	array(),
	is_array( $settings_operations ) ? $settings_operations : array(),
	is_array( $example_items_operations ) ? $example_items_operations : array()
);
