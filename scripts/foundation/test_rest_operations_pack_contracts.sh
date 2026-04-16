#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PERMISSIONS_CLASS_PATH="$ROOT_DIR/templates/child/rest-operations-pack/lib/wp-plugin-base/rest-operations/class-wp-plugin-base-rest-operations-permissions.php"
ERROR_LOG_PATH="$(mktemp)"

trap 'rm -f "$ERROR_LOG_PATH"' EXIT

PERMISSIONS_CLASS_PATH="$PERMISSIONS_CLASS_PATH" ERROR_LOG_PATH="$ERROR_LOG_PATH" php <<'PHP'
<?php
define( 'ABSPATH', '/' );

ini_set( 'log_errors', '1' );
ini_set( 'error_log', getenv( 'ERROR_LOG_PATH' ) );

class WP_Error {
  public $code;
  public $message;
  public $data;

  public function __construct( $code, $message, $data = array() ) {
    $this->code    = $code;
    $this->message = $message;
    $this->data    = $data;
  }
}

class WP_REST_Request {
  private $params = array();

  public function set_params( $params ) {
    $this->params = $params;
  }

  public function get_param( $key ) {
    return $this->params[ $key ] ?? null;
  }
}

function __( $text ) {
  return $text;
}

function is_wp_error( $value ) {
  return $value instanceof WP_Error;
}

$GLOBALS['wp_plugin_base_test_state'] = array(
  'is_user_logged_in' => true,
  'current_user_can'  => array(
    'manage_options' => false,
    'edit_posts'     => true,
  ),
  'current_user_id'   => 21,
  'user_meta'         => array(
    'example_plugin_rest_operation_scopes' => array( 'allow' => array( 'settings.*', 'items.read' ) ),
  ),
  'options'           => array(
    'example_plugin_rest_operation_scopes' => array( 'allow' => array( 'catalog.read' ) ),
  ),
);

function is_user_logged_in() {
  return $GLOBALS['wp_plugin_base_test_state']['is_user_logged_in'];
}

function current_user_can( $capability ) {
  return ! empty( $GLOBALS['wp_plugin_base_test_state']['current_user_can'][ $capability ] );
}

function get_current_user_id() {
  return $GLOBALS['wp_plugin_base_test_state']['current_user_id'];
}

function get_user_meta( $user_id, $key ) {
  unset( $user_id );
  return $GLOBALS['wp_plugin_base_test_state']['user_meta'][ $key ] ?? array();
}

function get_option( $key, $default = array() ) {
  return $GLOBALS['wp_plugin_base_test_state']['options'][ $key ] ?? $default;
}

function apply_filters( $hook_name, $value ) {
  if ( 'example-plugin_rest_granted_scopes' === $hook_name ) {
    $value[] = 'items.write';
  }

  return $value;
}

require getenv( 'PERMISSIONS_CLASS_PATH' );

$request = new WP_REST_Request();
$operation = array(
  'visibility'      => 'admin',
  'capability'      => 'edit_posts',
  'required_scopes' => array( 'settings.read', 'items.write' ),
);

$result = WP_Plugin_Base_REST_Operations_Permissions::check_operation( 'example-plugin', $operation, $request );
if ( true !== $result ) {
  fwrite( STDERR, "Expected wildcard and filtered scopes to satisfy all required scopes.\n" );
  exit( 1 );
}

$operation = array(
  'visibility'      => 'admin',
  'capability'      => 'edit_posts',
  'required_scopes' => array( 'settings.read', 'reports.export' ),
);

$result = WP_Plugin_Base_REST_Operations_Permissions::check_operation( 'example-plugin', $operation, $request );
if ( ! is_wp_error( $result ) || 'wp_plugin_base_rest_scope_forbidden' !== $result->code ) {
  fwrite( STDERR, "Expected missing required scope to fail.\n" );
  exit( 1 );
}

$operation = array(
  'visibility'      => 'admin',
  'required_scopes' => array( 'settings.read' ),
);

$result = WP_Plugin_Base_REST_Operations_Permissions::check_operation( 'example-plugin', $operation, $request );
if ( ! is_wp_error( $result ) || 'wp_plugin_base_rest_forbidden' !== $result->code ) {
  fwrite( STDERR, "Expected operations without a capability declaration to fail closed.\n" );
  exit( 1 );
}

$operation = array(
  'visibility'           => 'admin',
  'capability_callback'  => static function () {
    return new WP_Error( 'custom_capability_error', 'Capability callback failed.', array( 'status' => 418 ) );
  },
  'required_scopes'      => array( 'settings.read' ),
);

$result = WP_Plugin_Base_REST_Operations_Permissions::check_operation( 'example-plugin', $operation, $request );
if ( ! is_wp_error( $result ) || 'custom_capability_error' !== $result->code || 418 !== ( $result->data['status'] ?? null ) ) {
  fwrite( STDERR, "Expected capability_callback WP_Error responses to be preserved.\n" );
  exit( 1 );
}

$operation = array(
  'visibility'          => 'admin',
  'capability_callback' => static function () {
    return 'yes';
  },
  'required_scopes'     => array( 'settings.read' ),
);

$result = WP_Plugin_Base_REST_Operations_Permissions::check_operation( 'example-plugin', $operation, $request );
if ( ! is_wp_error( $result ) || 'wp_plugin_base_rest_forbidden' !== $result->code ) {
  fwrite( STDERR, "Expected truthy non-boolean capability_callback results to fail closed.\n" );
  exit( 1 );
}

$operation = array(
  'visibility'          => 'admin',
  'capability_callback' => static function () {
    throw new RuntimeException( 'Capability callback exploded.' );
  },
  'required_scopes'     => array( 'settings.read' ),
);

$result = WP_Plugin_Base_REST_Operations_Permissions::check_operation( 'example-plugin', $operation, $request );
if ( ! is_wp_error( $result ) || 'wp_plugin_base_rest_capability_check_failed' !== $result->code || 500 !== ( $result->data['status'] ?? null ) ) {
  fwrite( STDERR, "Expected thrown capability callbacks to fail with a normalized 500 WP_Error.\n" );
  exit( 1 );
}

$logged_output = file_get_contents( getenv( 'ERROR_LOG_PATH' ) );
if ( false === $logged_output || false === strpos( $logged_output, 'REST operation (unknown) capability_callback threw an uncaught RuntimeException.' ) ) {
  fwrite( STDERR, "Expected permission failures to log a sanitized exception class.\n" );
  exit( 1 );
}

if ( false !== strpos( $logged_output, 'Capability callback exploded.' ) ) {
  fwrite( STDERR, "Permission failure logs must not include raw exception messages.\n" );
  exit( 1 );
}

$GLOBALS['wp_plugin_base_test_state']['is_user_logged_in'] = false;
$operation = array(
  'visibility'      => 'public',
  'required_scopes' => array(),
);

$result = WP_Plugin_Base_REST_Operations_Permissions::check_operation( 'example-plugin', $operation, $request );
if ( true !== $result ) {
  fwrite( STDERR, "Expected public operation to allow anonymous access.\n" );
  exit( 1 );
}

echo "REST operations permission contract tests passed.\n";
PHP
