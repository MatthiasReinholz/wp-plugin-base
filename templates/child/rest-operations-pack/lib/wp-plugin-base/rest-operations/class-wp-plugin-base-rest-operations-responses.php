<?php
/**
 * REST operation response helpers.
 *
 * @package WPPluginBase
 * @since NEXT
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( ! class_exists( 'WP_Plugin_Base_REST_Operations_Responses' ) ) {
	/**
	 * Normalizes callback responses.
	 *
	 * @since NEXT
	 */
	class WP_Plugin_Base_REST_Operations_Responses {
		/**
		 * Wraps arbitrary callback output in a REST response when needed.
		 *
		 * @since NEXT
		 *
		 * @param mixed $result Callback result.
		 * @return WP_REST_Response|WP_Error|mixed
		 */
		public static function normalize( $result ) {
			if ( $result instanceof WP_REST_Response || is_wp_error( $result ) ) {
				return $result;
			}

			return new WP_REST_Response( $result, 200 );
		}

		/**
		 * Prepares REST transport output without changing non-opted-in WP_Error compatibility.
		 *
		 * @since NEXT
		 *
		 * @param WP_REST_Response|WP_Error|mixed $result Result payload.
		 * @param array<string,mixed>             $operation Operation manifest.
		 * @param WP_REST_Request                 $request Request instance.
		 * @return WP_REST_Response|WP_Error|mixed
		 */
		public static function prepare_rest_result( $result, array $operation, WP_REST_Request $request ) {
			if ( ! is_wp_error( $result ) || ! self::uses_error_envelope( $operation ) ) {
				return $result;
			}

			$request_id = self::resolve_request_id( $request );
			$status     = self::get_error_status( $result );
			$response   = new WP_REST_Response(
				array(
					'error' => array(
						'code'           => self::get_error_code( $result ),
						'message'        => self::get_public_error_message( $operation ),
						'status'         => $status,
						'request_id'     => $request_id,
						'correlation_id' => $request_id,
					),
				),
				$status
			);

			if ( method_exists( $response, 'header' ) ) {
				$response->header( 'X-Request-ID', $request_id );
				$response->header( 'X-Correlation-ID', $request_id );
			}

			return $response;
		}

		/**
		 * Unwraps a normalized response into raw data for non-REST transports.
		 *
		 * @since NEXT
		 *
		 * @param WP_REST_Response|WP_Error|mixed $result Result payload.
		 * @return WP_Error|mixed
		 */
		public static function unwrap( $result ) {
			if ( $result instanceof WP_REST_Response ) {
				return $result->get_data();
			}

			return $result;
		}

		/**
		 * Checks whether an operation opted into the safe error envelope.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $operation Operation manifest.
		 * @return bool
		 */
		private static function uses_error_envelope( array $operation ) {
			$error_response = isset( $operation['error_response'] ) ? $operation['error_response'] : array();

			return is_array( $error_response )
				&& isset( $error_response['mode'] )
				&& 'envelope' === $error_response['mode'];
		}

		/**
		 * Gets a safe public error message for opted-in operation envelopes.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $operation Operation manifest.
		 * @return string
		 */
		private static function get_public_error_message( array $operation ) {
			$error_response = isset( $operation['error_response'] ) && is_array( $operation['error_response'] )
				? $operation['error_response']
				: array();
			$message        = isset( $error_response['message'] ) ? trim( (string) $error_response['message'] ) : '';

			if ( '' !== $message ) {
				return $message;
			}

			return __( 'The REST operation failed.', '__PLUGIN_SLUG__' );
		}

		/**
		 * Resolves or creates a client-safe request id.
		 *
		 * @since NEXT
		 *
		 * @param WP_REST_Request $request Request instance.
		 * @return string
		 */
		private static function resolve_request_id( WP_REST_Request $request ) {
			$request_id = '';

			if ( method_exists( $request, 'get_header' ) ) {
				$request_id = (string) $request->get_header( 'x-correlation-id' );

				if ( '' === $request_id ) {
					$request_id = (string) $request->get_header( 'x-request-id' );
				}
			}

			$request_id = self::sanitize_request_id( $request_id );

			if ( '' !== $request_id ) {
				return $request_id;
			}

			if ( function_exists( 'wp_generate_uuid4' ) ) {
				$generated_request_id = self::sanitize_request_id( (string) wp_generate_uuid4() );

				if ( '' !== $generated_request_id ) {
					return $generated_request_id;
				}
			}

			try {
				return bin2hex( random_bytes( 16 ) );
			} catch ( Exception $error ) {
				unset( $error );
				return self::sanitize_request_id( uniqid( 'wp-plugin-base-', true ) );
			}
		}

		/**
		 * Sanitizes a request id for response data and headers.
		 *
		 * @since NEXT
		 *
		 * @param string $request_id Candidate request id.
		 * @return string
		 */
		private static function sanitize_request_id( $request_id ) {
			$request_id = substr( (string) $request_id, 0, 128 );
			$request_id = preg_replace( '/[^A-Za-z0-9._:-]/', '', $request_id );

			return is_string( $request_id ) ? $request_id : '';
		}

		/**
		 * Returns the REST status carried by a WP_Error.
		 *
		 * @since NEXT
		 *
		 * @param WP_Error $error Error object.
		 * @return int
		 */
		private static function get_error_status( WP_Error $error ) {
			$data = method_exists( $error, 'get_error_data' ) ? $error->get_error_data() : ( isset( $error->data ) ? $error->data : array() );

			if ( is_array( $data ) && isset( $data['status'] ) && is_numeric( $data['status'] ) ) {
				$status = (int) $data['status'];

				if ( $status >= 400 && $status <= 599 ) {
					return $status;
				}
			}

			return 500;
		}

		/**
		 * Returns the WP_Error code without exposing raw data.
		 *
		 * @since NEXT
		 *
		 * @param WP_Error $error Error object.
		 * @return string
		 */
		private static function get_error_code( WP_Error $error ) {
			if ( method_exists( $error, 'get_error_code' ) ) {
				return (string) $error->get_error_code();
			}

			return isset( $error->code ) ? (string) $error->code : 'wp_plugin_base_rest_error';
		}
	}
}
