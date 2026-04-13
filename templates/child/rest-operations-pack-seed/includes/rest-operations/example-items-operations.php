<?php
/**
 * Example list/detail operations.
 *
 * @package __PLUGIN_SLUG__
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( ! function_exists( 'wp_plugin_base_example_rest_operation_list_example_items' ) ) {
	/**
	 * Returns a small list/detail-friendly item collection.
	 *
	 * @param WP_REST_Request    $request Request object.
	 * @param array<string,mixed> $operation Operation manifest.
	 * @return array<string,mixed>
	 */
	function wp_plugin_base_example_rest_operation_list_example_items( $request, array $operation ) {
		unset( $request, $operation );

		return array(
			'items' => array(
				array(
					'id'          => 'overview',
					'name'        => __( 'Overview', '__PLUGIN_SLUG__' ),
					'description' => __( 'Summarizes the scaffolded runtime surface.', '__PLUGIN_SLUG__' ),
					'status'      => __( 'stable', '__PLUGIN_SLUG__' ),
				),
				array(
					'id'          => 'settings',
					'name'        => __( 'Settings', '__PLUGIN_SLUG__' ),
					'description' => __( 'Demonstrates a REST-backed settings workflow.', '__PLUGIN_SLUG__' ),
					'status'      => __( 'stable', '__PLUGIN_SLUG__' ),
				),
				array(
					'id'          => 'dataviews',
					'name'        => __( 'Data Views', '__PLUGIN_SLUG__' ),
					'description' => __( 'Reserved for a richer DataViews/DataForm experience when enabled.', '__PLUGIN_SLUG__' ),
					'status'      => 'true' === '__ADMIN_UI_EXPERIMENTAL_DATAVIEWS__'
						? __( 'enabled', '__PLUGIN_SLUG__' )
						: __( 'disabled', '__PLUGIN_SLUG__' ),
				),
			),
		);
	}
}

return array(
	array(
		'id'              => 'example-items.list',
		'route'           => '/example-items',
		'methods'         => 'GET',
		'callback'        => 'wp_plugin_base_example_rest_operation_list_example_items',
		'visibility'      => 'admin',
		'capability'      => 'manage_options',
		'required_scopes' => array( 'example-items.read' ),
		'output_schema'   => array(
			'type'       => 'object',
			'properties' => array(
				'items' => array(
					'type'  => 'array',
					'items' => array(
						'type'       => 'object',
						'properties' => array(
							'id'          => array( 'type' => 'string' ),
							'name'        => array( 'type' => 'string' ),
							'description' => array( 'type' => 'string' ),
							'status'      => array( 'type' => 'string' ),
						),
						'required'   => array( 'id', 'name', 'description', 'status' ),
					),
				),
			),
			'required'   => array( 'items' ),
		),
		'annotations'     => array(
			'readonly'    => true,
			'destructive' => false,
			'idempotent'  => true,
		),
		'ability'         => array(
			'name'         => '__PLUGIN_SLUG__/example-items-list',
			'label'        => __( 'List example items', '__PLUGIN_SLUG__' ),
			'description'  => __( 'Lists the example records used by the admin UI scaffold.', '__PLUGIN_SLUG__' ),
			'show_in_rest' => false,
		),
	),
);
