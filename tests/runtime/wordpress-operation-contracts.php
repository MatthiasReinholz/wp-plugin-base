<?php // phpcs:disable WordPress.Security.EscapeOutput -- CLI-only test diagnostics; no HTML output.
/**
 * Integration assertions executed inside a real WordPress installation by wp-env.
 *
 * @package WPPluginBase
 */

$operation = array(
	'id'              => 'contract.echo',
	'route'           => '/contract',
	'methods'         => 'POST',
	'visibility'      => 'admin',
	'capability'      => 'manage_options',
	'required_scopes' => array(),
	'callback'        => static function ( $request ) {
		return array(
			'message' => $request->get_param( 'message' ),
			'mode'    => $request->get_param( 'mode' ),
		);
	},
	'input_schema'    => array(
		'type'                 => 'object',
		'additionalProperties' => false,
		'maxProperties'        => 3,
		'properties'           => array(
			'message' => array(
				'type'      => 'string',
				'minLength' => 1,
			),
			'mode'    => array(
				'type'    => 'string',
				'default' => 'default-mode',
			),
			'nested'  => array(
				'type'                 => 'object',
				'properties'           => array(
					'count' => array(
						'type'    => 'integer',
						'minimum' => 1,
					),
				),
				'additionalProperties' => false,
				'required'             => array( 'count' ),
			),
		),
		'required'             => array( 'message' ),
	),
	'output_schema'   => array(
		'type'       => 'object',
		'properties' => array(
			'message' => array( 'type' => 'string' ),
			'mode'    => array( 'type' => 'string' ),
		),
		'required'   => array( 'message', 'mode' ),
	),
	'annotations'     => array(
		'readonly'    => true,
		'destructive' => false,
		'idempotent'  => true,
	),
	'ability'         => array(
		'name'         => 'runtime-pack-ready/contract-echo',
		'show_in_rest' => true,
	),
);

$required_default          = $operation;
$required_default['id']    = 'contract.required-default';
$required_default['route'] = '/contract-required-default';
$required_default['input_schema']['properties']['message']['default'] = 'must-still-be-supplied';
$required_default['ability']['name']                                  = 'runtime-pack-ready/contract-required-default';

$minimum_properties                                  = $operation;
$minimum_properties['id']                            = 'contract.minimum-properties';
$minimum_properties['route']                         = '/contract-minimum-properties';
$minimum_properties['input_schema']['minProperties'] = 2;
$minimum_properties['ability']['name']               = 'runtime-pack-ready/contract-minimum-properties';

$invalid_output                    = $operation;
$invalid_output['id']              = 'contract.invalid-output';
$invalid_output['route']           = '/contract-invalid-output';
$invalid_output['callback']        = static function () {
	return array( 'message' => 123 );
};
$invalid_output['ability']['name'] = 'runtime-pack-ready/contract-invalid-output';

$nullable                    = $operation;
$nullable['id']              = 'contract.nullable';
$nullable['route']           = '/contract-nullable';
$nullable['ability']['name'] = 'runtime-pack-ready/contract-nullable';
$nullable['input_schema']['properties']['message']['type']  = array( 'string', 'null' );
$nullable['output_schema']['properties']['message']['type'] = array( 'string', 'null' );

$legacy_nullable                    = $nullable;
$legacy_nullable['id']              = 'contract.legacy-nullable';
$legacy_nullable['route']           = '/contract-legacy-nullable';
$legacy_nullable['ability']['name'] = 'runtime-pack-ready/contract-legacy-nullable';
$legacy_nullable['input_schema']['properties']['message']['required'] = true;
unset( $legacy_nullable['input_schema']['required'] );

$normalized                    = $operation;
$normalized['id']              = 'contract.normalized';
$normalized['route']           = '/contract-normalized';
$normalized['ability']['name'] = 'runtime-pack-ready/contract-normalized';
$normalized['input_schema']['properties']['message']['format']    = 'text-field';
$normalized['input_schema']['properties']['message']['minLength'] = 3;

$invalid_default                    = $operation;
$invalid_default['id']              = 'contract.invalid-default';
$invalid_default['route']           = '/contract-invalid-default';
$invalid_default['ability']['name'] = 'runtime-pack-ready/contract-invalid-default';
$invalid_default['input_schema']['properties']['mode']['minLength'] = 3;
$invalid_default['input_schema']['properties']['mode']['default']   = 'x';

$operations = array( $operation, $required_default, $minimum_properties, $invalid_output, $nullable, $legacy_nullable, $normalized, $invalid_default );
add_action(
	'rest_api_init',
	static function () use ( $operations ) {
		Runtime_Pack_Test_WP_Plugin_Base_REST_Operations_REST_Adapter::register_all( 'runtime-pack-ready', 'runtime-pack-ready/v1', $operations );
	}
);
add_action(
	'wp_abilities_api_init',
	static function () use ( $operations ) {
		Runtime_Pack_Test_WP_Plugin_Base_REST_Operations_Abilities_Adapter::register_operations( 'runtime-pack-ready', 'runtime-pack-ready', $operations );
	}
);

$has_abilities = function_exists( 'wp_get_ability' );
if ( version_compare( $GLOBALS['wp_version'], '6.9', '>=' ) && ! $has_abilities ) {
	throw new RuntimeException( 'The configured WordPress version should provide core Abilities.' );
}

wp_set_current_user( 1 );
$ability = $has_abilities ? wp_get_ability( 'runtime-pack-ready/contract-echo' ) : null;
if ( $has_abilities ) {
	if ( ! $ability instanceof WP_Ability || true !== $ability->get_meta_item( 'show_in_rest' ) || true !== $ability->get_meta_item( 'annotations' )['readonly'] ) {
		throw new RuntimeException( 'Core rejected the registered ability or lost its metadata.' );
	}
	$seed_ability = wp_get_ability( 'runtime-pack-ready/settings-read' );
	if ( ! $seed_ability instanceof WP_Ability || false !== $seed_ability->get_meta_item( 'show_in_rest' ) ) {
		throw new RuntimeException( 'Expected the seeded ability to be registered and hidden from REST.' );
	}
	wp_set_current_user( 0 );
	if ( ! is_wp_error( $ability->check_permissions( array( 'message' => 'hello' ) ) ) ) {
		throw new RuntimeException( 'Anonymous ability permission checks unexpectedly succeeded.' );
	}
	// Core reports the intentionally denied WP_Error as a developer notice.
	add_filter( 'doing_it_wrong_trigger_error', '__return_false' );
	$denied = $ability->execute( array( 'message' => 'hello' ) );
	remove_filter( 'doing_it_wrong_trigger_error', '__return_false' );
	if ( ! is_wp_error( $denied ) || 'ability_invalid_permissions' !== $denied->get_error_code() ) {
		throw new RuntimeException( 'Core executed an unauthorized operation.' );
	}
	wp_set_current_user( 1 );
}

$cases = array(
	array( array( 'message' => 'hello' ), true ),
	array( array(), false ),
	array(
		array(
			'message' => 'hello',
			'extra'   => 'forbidden',
		),
		false,
	),
	array(
		array(
			'message' => 'hello',
			'nested'  => array( 'count' => 2 ),
		),
		true,
	),
	array(
		array(
			'message' => 'hello',
			'nested'  => array( 'count' => 0 ),
		),
		false,
	),
	array(
		array(
			'message' => 'hello',
			'nested'  => array(
				'count' => 2,
				'extra' => true,
			),
		),
		false,
	),
	array( array( 'message' => array( 'bad' ) ), false ),
);
foreach ( $cases as $index => $case ) {
	$request = new WP_REST_Request( 'POST', '/runtime-pack-ready/v1/contract' );
	$request->set_body_params( $case[0] );
	$response = rest_do_request( $request );
	if ( ( $case[1] ? 200 : 400 ) !== $response->get_status() ) {
		throw new RuntimeException( 'REST schema contract failed case ' . $index . ': ' . wp_json_encode( $response->get_data() ) );
	}
	if ( $has_abilities ) {
		$result = $ability->execute( $case[0] );
		if ( is_wp_error( $result ) === $case[1] ) {
			throw new RuntimeException( 'Abilities and REST disagree about schema case ' . $index );
		}
		if ( $case[1] && $result !== $response->get_data() ) {
			throw new RuntimeException( 'Abilities and REST normalized input differently.' );
		}
	}
}
foreach ( array(
	'required-default'   => array(),
	'minimum-properties' => array( 'message' => 'hello' ),
) as $name => $input ) {
	$request = new WP_REST_Request( 'POST', '/runtime-pack-ready/v1/contract-' . $name );
	$request->set_body_params( $input );
	if ( 400 !== rest_do_request( $request )->get_status() || ( $has_abilities && ! is_wp_error( wp_get_ability( 'runtime-pack-ready/contract-' . $name )->execute( $input ) ) ) ) {
		throw new RuntimeException( 'Defaults bypassed raw input validation for ' . $name );
	}
}

foreach ( array(
	array( 'nullable', array( 'message' => null ), true ),
	array( 'nullable', array(), false ),
	array( 'legacy-nullable', array( 'message' => null ), true ),
	array( 'legacy-nullable', array(), false ),
	array( 'echo', array( 'message' => null ), false ),
	array( 'normalized', array( 'message' => '  x  ' ), false ),
	array( 'normalized', array( 'message' => '  valid  ' ), true ),
	array( 'invalid-default', array( 'message' => 'valid' ), false ),
) as $case ) {
	$route   = 'echo' === $case[0] ? '/contract' : '/contract-' . $case[0];
	$request = new WP_REST_Request( 'POST', '/runtime-pack-ready/v1' . $route );
	$request->set_body_params( $case[1] );
	$response = rest_do_request( $request );
	if ( ( $case[2] ? 200 : 400 ) !== $response->get_status() ) {
		throw new RuntimeException( 'REST normalized schema contract failed for ' . $case[0] . ': ' . wp_json_encode( $response->get_data() ) );
	}
	if ( $has_abilities ) {
		$result = wp_get_ability( 'runtime-pack-ready/contract-' . $case[0] )->execute( $case[1] );
		if ( is_wp_error( $result ) === $case[2] || ( $case[2] && $result !== $response->get_data() ) ) {
			throw new RuntimeException( 'Abilities and REST disagree on normalized schema for ' . $case[0] );
		}
	}
}
$request = new WP_REST_Request( 'POST', '/runtime-pack-ready/v1/contract' );
$request->set_body_params( array( 'message' => 'hello' ) );
$request->set_query_params(
	array(
		'_fields' => 'message,mode',
		'_locale' => 'user',
	)
);
if ( 200 !== rest_do_request( $request )->get_status() ) {
	throw new RuntimeException( 'WordPress transport controls should not violate the operation schema.' );
}
if ( $has_abilities ) {
	$invalid_result = wp_get_ability( 'runtime-pack-ready/contract-invalid-output' )->execute( array( 'message' => 'hello' ) );
	if ( ! is_wp_error( $invalid_result ) || 'ability_invalid_output' !== $invalid_result->get_error_code() ) {
		throw new RuntimeException( 'Core failed to enforce the declared output schema.' );
	}
	foreach ( array(
		'contract-echo' => 200,
		'settings-read' => 404,
	) as $name => $expected_status ) {
		$response = rest_do_request( new WP_REST_Request( 'GET', '/wp-abilities/v1/abilities/runtime-pack-ready/' . $name ) );
		if ( $response->get_status() !== $expected_status ) {
			throw new RuntimeException( 'Core REST exposure ignored show_in_rest for ' . $name );
		}
	}
}
wp_set_current_user( 0 );
echo 'Real WordPress schema and Abilities contracts passed on ' . $GLOBALS['wp_version'] . ' / PHP ' . PHP_VERSION . PHP_EOL;
