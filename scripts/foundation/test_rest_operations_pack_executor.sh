#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESPONSES_CLASS_PATH="$ROOT_DIR/templates/child/rest-operations-pack/lib/wp-plugin-base/rest-operations/class-wp-plugin-base-rest-operations-responses.php"
EXECUTOR_CLASS_PATH="$ROOT_DIR/templates/child/rest-operations-pack/lib/wp-plugin-base/rest-operations/class-wp-plugin-base-rest-operations-executor.php"
ERROR_LOG_PATH="$(mktemp)"

trap 'rm -f "$ERROR_LOG_PATH"' EXIT

RESPONSES_CLASS_PATH="$RESPONSES_CLASS_PATH" EXECUTOR_CLASS_PATH="$EXECUTOR_CLASS_PATH" ERROR_LOG_PATH="$ERROR_LOG_PATH" php <<'PHP'
<?php
define( 'ABSPATH', '/' );

ini_set( 'log_errors', '1' );
ini_set( 'error_log', getenv( 'ERROR_LOG_PATH' ) );

class WP_REST_Request {}

class WP_REST_Response {
  private $data;
  private $status;

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
}

function __( $text ) {
  return $text;
}

function is_wp_error( $value ) {
  return $value instanceof WP_Error;
}

require getenv( 'RESPONSES_CLASS_PATH' );
require getenv( 'EXECUTOR_CLASS_PATH' );

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

echo "REST operations executor tests passed.\n";
PHP
