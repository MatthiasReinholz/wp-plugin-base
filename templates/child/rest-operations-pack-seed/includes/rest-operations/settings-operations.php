<?php
/**
 * Example settings operations.
 *
 * @package __PLUGIN_SLUG__
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( ! function_exists( 'wp_plugin_base_example_rest_operation_get_settings' ) ) {
	/**
	 * Returns the current demo settings payload.
	 *
	 * @param WP_REST_Request    $request Request object.
	 * @param array<string,mixed> $operation Operation manifest.
	 * @return array<string,mixed>
	 */
	function wp_plugin_base_example_rest_operation_get_settings( $request, array $operation ) {
		unset( $request, $operation );

		return array(
			'message' => (string) get_option(
				'__PLUGIN_SLUG___admin_message',
				__( 'Welcome to __PLUGIN_NAME__.', '__PLUGIN_SLUG__' )
			),
			'version' => defined( '__VERSION_CONSTANT_NAME__' ) ? constant( '__VERSION_CONSTANT_NAME__' ) : '',
		);
	}
}

if ( ! function_exists( 'wp_plugin_base_example_rest_operation_update_settings' ) ) {
	/**
	 * Updates the demo settings payload.
	 *
	 * @param WP_REST_Request    $request Request object.
	 * @param array<string,mixed> $operation Operation manifest.
	 * @return array<string,mixed>
	 */
	function wp_plugin_base_example_rest_operation_update_settings( $request, array $operation ) {
		unset( $operation );

		$message = (string) $request->get_param( 'message' );
		$message = sanitize_text_field( $message );

		update_option( '__PLUGIN_SLUG___admin_message', $message );

		return array(
			'message' => $message,
			'updated' => true,
		);
	}
}

return array(
	array(
		'id'              => 'settings.read',
		'route'           => '/settings',
		'methods'         => 'GET',
		'callback'        => 'wp_plugin_base_example_rest_operation_get_settings',
		'visibility'      => 'admin',
		'capability'      => 'manage_options',
		'required_scopes' => array( 'settings.read' ),
		'output_schema'   => array(
			'type'       => 'object',
			'properties' => array(
				'message' => array(
					'type' => 'string',
				),
				'version' => array(
					'type' => 'string',
				),
			),
			'required'   => array( 'message', 'version' ),
		),
		'annotations'     => array(
			'readonly'   => true,
			'destructive' => false,
			'idempotent' => true,
		),
		'ability'         => array(
			'name'         => '__PLUGIN_SLUG__/settings-read',
			'label'        => __( 'Read settings', '__PLUGIN_SLUG__' ),
			'description'  => __( 'Reads the current plugin settings payload.', '__PLUGIN_SLUG__' ),
			'show_in_rest' => false,
		),
	),
	array(
		'id'              => 'settings.update',
		'route'           => '/settings',
		'methods'         => 'POST',
		'callback'        => 'wp_plugin_base_example_rest_operation_update_settings',
		'visibility'      => 'admin',
		'capability'      => 'manage_options',
		'required_scopes' => array( 'settings.update' ),
		'input_schema'    => array(
			'type'       => 'object',
			'properties' => array(
				'message' => array(
					'type'      => 'string',
					'minLength' => 1,
				),
			),
			'required'   => array( 'message' ),
		),
		'output_schema'   => array(
			'type'       => 'object',
			'properties' => array(
				'message' => array(
					'type' => 'string',
				),
				'updated' => array(
					'type' => 'boolean',
				),
			),
			'required'   => array( 'message', 'updated' ),
		),
		'annotations'     => array(
			'readonly'   => false,
			'destructive' => false,
			'idempotent' => true,
		),
		'ability'         => array(
			'name'         => '__PLUGIN_SLUG__/settings-update',
			'label'        => __( 'Update settings', '__PLUGIN_SLUG__' ),
			'description'  => __( 'Updates the current plugin settings payload.', '__PLUGIN_SLUG__' ),
			'show_in_rest' => false,
		),
	),
);
