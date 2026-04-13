#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INPUT_CLASS_PATH="$ROOT_DIR/templates/child/rest-operations-pack/lib/wp-plugin-base/rest-operations/class-wp-plugin-base-rest-operations-input.php"
PERMISSIONS_CLASS_PATH="$ROOT_DIR/templates/child/rest-operations-pack/lib/wp-plugin-base/rest-operations/class-wp-plugin-base-rest-operations-permissions.php"
RESPONSES_CLASS_PATH="$ROOT_DIR/templates/child/rest-operations-pack/lib/wp-plugin-base/rest-operations/class-wp-plugin-base-rest-operations-responses.php"
EXECUTOR_CLASS_PATH="$ROOT_DIR/templates/child/rest-operations-pack/lib/wp-plugin-base/rest-operations/class-wp-plugin-base-rest-operations-executor.php"
ABILITIES_CLASS_PATH="$ROOT_DIR/templates/child/rest-operations-pack/lib/wp-plugin-base/rest-operations/class-wp-plugin-base-rest-operations-abilities-adapter.php"

INPUT_CLASS_PATH="$INPUT_CLASS_PATH" PERMISSIONS_CLASS_PATH="$PERMISSIONS_CLASS_PATH" RESPONSES_CLASS_PATH="$RESPONSES_CLASS_PATH" EXECUTOR_CLASS_PATH="$EXECUTOR_CLASS_PATH" ABILITIES_CLASS_PATH="$ABILITIES_CLASS_PATH" php <<'PHP'
<?php
define( 'ABSPATH', '/' );

class WP_REST_Request {
  public $method;
  public $route;
  public $params = array();

  public function __construct( $method = '', $route = '' ) {
    $this->method = $method;
    $this->route  = $route;
  }

  public function set_params( $params ) {
    $this->params = $params;
  }

  public function get_param( $key ) {
    return $this->params[ $key ] ?? null;
  }
}

class WP_REST_Response {
  private $data;

  public function __construct( $data ) {
    $this->data = $data;
  }

  public function get_data() {
    return $this->data;
  }
}

class WP_Error {
  public $code;
  public $message;
  public $data;

  public function __construct( $code, $message = '', $data = array() ) {
    $this->code    = $code;
    $this->message = $message;
    $this->data    = $data;
  }
}

function __( $text ) {
  return $text;
}

function is_wp_error( $value ) {
  return $value instanceof WP_Error;
}

function wp_register_ability_category( $slug, $args ) {
  $GLOBALS['wp_plugin_base_registered_ability_categories'][ $slug ] = $args;
}

function wp_register_ability( $name, $args ) {
  $GLOBALS['wp_plugin_base_registered_abilities'][ $name ] = $args;
}

function is_user_logged_in() {
  return true;
}

function current_user_can( $capability ) {
  return 'manage_options' === $capability;
}

function get_current_user_id() {
  return 1;
}

function get_user_meta() {
  return array();
}

function get_option( $key, $default = array() ) {
  if ( 'example_plugin_rest_operation_scopes' === $key ) {
    return array( 'allow' => array( 'settings.read' ) );
  }

  return $default;
}

function apply_filters( $hook_name, $value ) {
  unset( $hook_name );
  return $value;
}

function rest_validate_value_from_schema( $value, $schema, $param ) {
  if ( ! is_array( $value ) ) {
    return new WP_Error( 'rest_invalid_param', "{$param} must be an object." );
  }

  $required_fields = isset( $schema['required'] ) && is_array( $schema['required'] )
    ? $schema['required']
    : array();

  foreach ( $required_fields as $required_field ) {
    if ( ! array_key_exists( $required_field, $value ) || '' === $value[ $required_field ] ) {
      return new WP_Error( 'rest_invalid_param', "Missing required field {$required_field}." );
    }
  }

  return true;
}

function rest_sanitize_value_from_schema( $value, $schema, $param ) {
  unset( $schema, $param );
  return $value;
}

require getenv( 'INPUT_CLASS_PATH' );
require getenv( 'PERMISSIONS_CLASS_PATH' );
require getenv( 'RESPONSES_CLASS_PATH' );
require getenv( 'EXECUTOR_CLASS_PATH' );
require getenv( 'ABILITIES_CLASS_PATH' );

function wp_plugin_base_example_rest_operation_get_settings( $request ) {
  return new WP_REST_Response(
    array(
      'message' => (string) $request->get_param( 'message' ),
    )
  );
}

$operation = array(
  array(
    'id'              => 'settings.read',
    'methods'         => 'GET',
    'route'           => '/settings',
    'callback'        => 'wp_plugin_base_example_rest_operation_get_settings',
    'visibility'      => 'admin',
    'capability'      => 'manage_options',
    'required_scopes' => array( 'settings.read' ),
      'output_schema'   => array(
        'type'       => 'object',
        'properties' => array(
          'message' => array( 'type' => 'string' ),
        ),
      ),
      'input_schema'    => array(
        'type'       => 'object',
        'properties' => array(
          'message' => array( 'type' => 'string' ),
        ),
        'required'   => array( 'message' ),
      ),
      'ability'         => array(
        'name'         => 'example/settings-read',
        'label'        => 'Read settings',
      'description'  => 'Reads settings.',
      'show_in_rest' => true,
    ),
  ),
);

WP_Plugin_Base_REST_Operations_Abilities_Adapter::register_category( 'example-plugin', 'Example Plugin' );
WP_Plugin_Base_REST_Operations_Abilities_Adapter::register_operations( 'example-plugin', 'example-plugin', $operation );

if ( empty( $GLOBALS['wp_plugin_base_registered_ability_categories']['example-plugin'] ) ) {
  fwrite( STDERR, "Expected ability category registration.\n" );
  exit( 1 );
}

if ( empty( $GLOBALS['wp_plugin_base_registered_abilities']['example/settings-read'] ) ) {
  fwrite( STDERR, "Expected ability registration.\n" );
  exit( 1 );
}

$ability = $GLOBALS['wp_plugin_base_registered_abilities']['example/settings-read'];
if ( empty( $ability['execute_callback'] ) || ! is_callable( $ability['execute_callback'] ) ) {
  fwrite( STDERR, "Expected execute callback to be registered.\n" );
  exit( 1 );
}

$result = $ability['execute_callback']( array( 'message' => 'Hello' ) );
if ( ! is_array( $result ) || 'Hello' !== $result['message'] ) {
  fwrite( STDERR, "Expected execute callback to unwrap the normalized REST response payload.\n" );
  exit( 1 );
}

$invalid_result = $ability['execute_callback']( array() );
if ( ! is_wp_error( $invalid_result ) || 'rest_invalid_param' !== $invalid_result->code ) {
  fwrite( STDERR, "Expected execute callback to reject input that violates the declared input schema.\n" );
  exit( 1 );
}

echo "REST operations abilities adapter tests passed.\n";
PHP
