#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESPONSES_CLASS_PATH="$ROOT_DIR/templates/child/rest-operations-pack/lib/wp-plugin-base/rest-operations/class-wp-plugin-base-rest-operations-responses.php"
INPUT_CLASS_PATH="$ROOT_DIR/templates/child/rest-operations-pack/lib/wp-plugin-base/rest-operations/class-wp-plugin-base-rest-operations-input.php"
EXECUTOR_CLASS_PATH="$ROOT_DIR/templates/child/rest-operations-pack/lib/wp-plugin-base/rest-operations/class-wp-plugin-base-rest-operations-executor.php"
REST_ADAPTER_CLASS_PATH="$ROOT_DIR/templates/child/rest-operations-pack/lib/wp-plugin-base/rest-operations/class-wp-plugin-base-rest-operations-rest-adapter.php"
ERROR_LOG_PATH="$(mktemp)"

trap 'rm -f "$ERROR_LOG_PATH"' EXIT

RESPONSES_CLASS_PATH="$RESPONSES_CLASS_PATH" INPUT_CLASS_PATH="$INPUT_CLASS_PATH" EXECUTOR_CLASS_PATH="$EXECUTOR_CLASS_PATH" REST_ADAPTER_CLASS_PATH="$REST_ADAPTER_CLASS_PATH" ERROR_LOG_PATH="$ERROR_LOG_PATH" php <<'PHP'
<?php
define( 'ABSPATH', '/' );

ini_set( 'log_errors', '1' );
ini_set( 'error_log', getenv( 'ERROR_LOG_PATH' ) );

class WP_REST_Request {
  private $headers = array();

  public function set_header( $key, $value ) {
    $this->headers[ strtolower( $key ) ] = $value;
  }

  public function get_header( $key ) {
    return $this->headers[ strtolower( $key ) ] ?? '';
  }
}

class WP_REST_Response {
  private $data;
  private $status;
  private $headers = array();

  public function __construct( $data, $status = 200 ) {
    $this->data   = $data;
    $this->status = $status;
  }

  public function get_data() {
    return $this->data;
  }

  public function get_status() {
    return $this->status;
  }

  public function header( $key, $value ) {
    $this->headers[ $key ] = $value;
  }

  public function get_headers() {
    return $this->headers;
  }
}

class WP_Error {
  public $code;
  public $message;
  public $data;

  public function __construct( $code, $message, $data = array() ) {
    $this->code    = $code;
    $this->message = $message;
    $this->data    = $data;
  }

  public function get_error_code() {
    return $this->code;
  }

  public function get_error_data() {
    return $this->data;
  }
}

function __( $text ) {
  return $text;
}

function is_wp_error( $value ) {
  return $value instanceof WP_Error;
}

function register_rest_route( $namespace, $route, $args ) {
  $GLOBALS['wp_plugin_base_registered_rest_route'] = array(
    'namespace' => $namespace,
    'route'     => $route,
    'args'      => $args,
  );
}

require getenv( 'RESPONSES_CLASS_PATH' );
require getenv( 'INPUT_CLASS_PATH' );
require getenv( 'EXECUTOR_CLASS_PATH' );
require getenv( 'REST_ADAPTER_CLASS_PATH' );

$request = new WP_REST_Request();

$result = WP_Plugin_Base_REST_Operations_Executor::execute(
  array(
    'id'       => 'settings.read',
    'callback' => static function () {
      return array( 'message' => 'Hello' );
    },
  ),
  $request
);

if ( ! ( $result instanceof WP_REST_Response ) || 200 !== $result->get_status() || 'Hello' !== $result->get_data()['message'] ) {
  fwrite( STDERR, "Expected executor to normalize callback arrays into a 200 REST response.\n" );
  exit( 1 );
}

$invalid_callback_result = WP_Plugin_Base_REST_Operations_Executor::execute(
  array(
    'id'       => 'settings.invalid',
    'callback' => 'wp_plugin_base_missing_callback',
  ),
  $request
);

if ( ! is_wp_error( $invalid_callback_result ) || 'wp_plugin_base_rest_invalid_callback' !== $invalid_callback_result->code || 500 !== ( $invalid_callback_result->data['status'] ?? null ) ) {
  fwrite( STDERR, "Expected invalid callbacks to fail with a normalized 500 WP_Error.\n" );
  exit( 1 );
}

$thrown_callback_result = WP_Plugin_Base_REST_Operations_Executor::execute(
  array(
    'id'       => 'settings.throwing',
    'callback' => static function () {
      throw new RuntimeException( 'Boom' );
    },
  ),
  $request
);

if ( ! is_wp_error( $thrown_callback_result ) || 'wp_plugin_base_rest_execution_failed' !== $thrown_callback_result->code || 500 !== ( $thrown_callback_result->data['status'] ?? null ) ) {
  fwrite( STDERR, "Expected thrown callbacks to fail with a normalized 500 WP_Error.\n" );
  exit( 1 );
}

$logged_output = file_get_contents( getenv( 'ERROR_LOG_PATH' ) );
if ( false === $logged_output || false === strpos( $logged_output, 'REST operation settings.throwing threw an uncaught RuntimeException.' ) ) {
  fwrite( STDERR, "Expected executor failures to log a sanitized operation id + exception class.\n" );
  exit( 1 );
}

if ( false !== strpos( $logged_output, 'Boom' ) ) {
  fwrite( STDERR, "Executor failure logs must not include raw exception messages.\n" );
  exit( 1 );
}

$raw_error = new WP_Error(
  'provider_failed',
  'Raw upstream response with secret sk_live_123.',
  array(
    'status'       => 502,
    'upstreamBody' => '{ "token": "secret" }',
  )
);

$default_error_result = WP_Plugin_Base_REST_Operations_Responses::prepare_rest_result(
  $raw_error,
  array( 'id' => 'settings.default-error' ),
  $request
);

if ( $raw_error !== $default_error_result ) {
  fwrite( STDERR, "Expected default REST error handling to preserve WP_Error compatibility.\n" );
  exit( 1 );
}

$request->set_header( 'X-Correlation-ID', 'trace 123<script>' );
$enveloped_result = WP_Plugin_Base_REST_Operations_Responses::prepare_rest_result(
  $raw_error,
  array(
    'id'             => 'settings.safe-error',
    'error_response' => array(
      'mode'    => 'envelope',
      'message' => 'Settings request failed.',
    ),
  ),
  $request
);

if ( ! ( $enveloped_result instanceof WP_REST_Response ) || 502 !== $enveloped_result->get_status() ) {
  fwrite( STDERR, "Expected opted-in WP_Error results to return an error envelope REST response with the WP_Error status.\n" );
  exit( 1 );
}

$enveloped_payload = $enveloped_result->get_data();
$request_id        = $enveloped_payload['error']['request_id'] ?? '';
$headers           = $enveloped_result->get_headers();

if (
  'provider_failed' !== ( $enveloped_payload['error']['code'] ?? '' )
  || 'Settings request failed.' !== ( $enveloped_payload['error']['message'] ?? '' )
  || 502 !== ( $enveloped_payload['error']['status'] ?? null )
  || 'trace123script' !== $request_id
  || 'trace123script' !== ( $enveloped_payload['error']['correlation_id'] ?? '' )
  || 'trace123script' !== ( $headers['X-Request-ID'] ?? '' )
  || 'trace123script' !== ( $headers['X-Correlation-ID'] ?? '' )
) {
  fwrite( STDERR, "Expected opted-in error envelopes to include only code, safe message, status, and sanitized request/correlation id data/headers.\n" );
  exit( 1 );
}

$encoded_payload = json_encode( $enveloped_payload );
if ( false === $encoded_payload || false !== strpos( $encoded_payload, 'sk_live_123' ) || false !== strpos( $encoded_payload, 'upstreamBody' ) ) {
  fwrite( STDERR, "Error envelopes must not expose raw WP_Error messages or upstream payload data.\n" );
  exit( 1 );
}

$bad_status_result = WP_Plugin_Base_REST_Operations_Responses::prepare_rest_result(
  new WP_Error( 'provider_bad_status', 'Raw provider error.', array( 'status' => 201 ) ),
  array(
    'id'             => 'settings.bad-status',
    'error_response' => array(
      'mode' => 'envelope',
    ),
  ),
  $request
);

if ( ! ( $bad_status_result instanceof WP_REST_Response ) || 500 !== $bad_status_result->get_status() || 'The REST operation failed.' !== ( $bad_status_result->get_data()['error']['message'] ?? '' ) ) {
  fwrite( STDERR, "Expected error envelopes to reject non-error statuses and use the generic fallback message when none is configured.\n" );
  exit( 1 );
}

WP_Plugin_Base_REST_Operations_REST_Adapter::register_all(
  'example-plugin',
  'example/v1',
  array(
    array(
      'id'             => 'settings.adapter-safe-error',
      'route'          => '/settings',
      'methods'        => 'GET',
      'callback'       => static function () use ( $raw_error ) {
        return $raw_error;
      },
      'error_response' => array(
        'mode'    => 'envelope',
        'message' => 'Adapter request failed.',
      ),
    ),
  )
);

$registered_route = $GLOBALS['wp_plugin_base_registered_rest_route'] ?? null;
if (
  ! is_array( $registered_route )
  || 'example/v1' !== ( $registered_route['namespace'] ?? '' )
  || '/settings' !== ( $registered_route['route'] ?? '' )
  || ! is_callable( $registered_route['args']['callback'] ?? null )
) {
  fwrite( STDERR, "Expected REST adapter to register a callable operation route.\n" );
  exit( 1 );
}

$adapter_result = $registered_route['args']['callback']( $request );
if ( ! ( $adapter_result instanceof WP_REST_Response ) || 'Adapter request failed.' !== ( $adapter_result->get_data()['error']['message'] ?? '' ) ) {
  fwrite( STDERR, "Expected REST adapter callbacks to apply opted-in error envelopes.\n" );
  exit( 1 );
}

echo "REST operations executor tests passed.\n";
PHP
