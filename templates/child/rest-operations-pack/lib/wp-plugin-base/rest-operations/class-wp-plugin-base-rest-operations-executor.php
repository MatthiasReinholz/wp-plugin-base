<?php
/**
 * Shared operation execution helpers.
 *
 * @package WPPluginBase
 * @since NEXT
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( ! class_exists( 'WP_Plugin_Base_REST_Operations_Executor' ) ) {
	/**
	 * Executes operation callbacks consistently across transports.
	 *
	 * @since NEXT
	 */
	class WP_Plugin_Base_REST_Operations_Executor {
		/**
		 * Runs an operation callback and normalizes the result.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $operation Operation manifest.
		 * @param WP_REST_Request     $request Request instance.
		 * @return WP_REST_Response|WP_Error
		 */
		public static function execute( array $operation, WP_REST_Request $request ) {
			if ( empty( $operation['callback'] ) || ! is_callable( $operation['callback'] ) ) {
				return new WP_Error(
					'wp_plugin_base_rest_invalid_callback',
					__( 'The REST operation callback is invalid.', '__PLUGIN_SLUG__' ),
					array( 'status' => 500 )
				);
			}

			try {
				$result = call_user_func( $operation['callback'], $request, $operation );
			} catch ( Throwable $error ) {
				self::log_execution_failure( $operation, $error );

				return new WP_Error(
					'wp_plugin_base_rest_execution_failed',
					__( 'The REST operation failed to execute.', '__PLUGIN_SLUG__' ),
					array( 'status' => 500 )
				);
			}

			return WP_Plugin_Base_REST_Operations_Responses::normalize( $result );
		}

		/**
		 * Logs uncaught execution failures for developer visibility.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $operation Operation manifest.
		 * @param Throwable           $error     Thrown error.
		 * @return void
		 */
		private static function log_execution_failure( array $operation, Throwable $error ) {
			$operation_id = isset( $operation['id'] ) ? (string) $operation['id'] : '(unknown)';
			$error_class  = get_class( $error );
			$message      = sprintf(
				/* translators: 1: operation id, 2: thrown exception class name. */
				__( 'REST operation %1$s threw an uncaught %2$s.', '__PLUGIN_SLUG__' ),
				$operation_id,
				$error_class
			);

			// phpcs:ignore WordPress.PHP.DevelopmentFunctions.error_log_error_log -- Intentional runtime logging for uncaught operation exceptions.
			error_log( $message );
		}
	}
}
