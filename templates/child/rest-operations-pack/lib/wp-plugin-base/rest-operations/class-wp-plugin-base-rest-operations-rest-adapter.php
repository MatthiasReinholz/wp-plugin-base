<?php
/**
 * REST adapter for operation manifests.
 *
 * @package WPPluginBase
 * @since NEXT
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( ! class_exists( 'WP_Plugin_Base_REST_Operations_REST_Adapter' ) ) {
	/**
	 * Registers REST routes from operation manifests.
	 *
	 * @since NEXT
	 */
	class WP_Plugin_Base_REST_Operations_REST_Adapter {
		/**
		 * Registers all operations with the REST API.
		 *
		 * @since NEXT
		 *
		 * @param string                         $plugin_slug Plugin slug.
		 * @param string                         $rest_namespace REST namespace.
		 * @param array<int,array<string,mixed>> $operations Operations.
		 * @return void
		 */
		public static function register_all( $plugin_slug, $rest_namespace, array $operations ) {
			foreach ( $operations as $operation ) {
				self::register_operation( $plugin_slug, $rest_namespace, $operation );
			}
		}

		/**
		 * Registers a single operation.
		 *
		 * @since NEXT
		 *
		 * @param string              $plugin_slug    Plugin slug.
		 * @param string              $rest_namespace REST namespace.
		 * @param array<string,mixed> $operation      Operation manifest.
		 * @return void
		 */
		private static function register_operation( $plugin_slug, $rest_namespace, array $operation ) {
			if ( empty( $operation['route'] ) || empty( $operation['callback'] ) || ! is_callable( $operation['callback'] ) ) {
				self::report_invalid_operation( $operation );
				return;
			}

			register_rest_route(
				$rest_namespace,
				$operation['route'],
				array(
					'methods'             => $operation['methods'],
					'callback'            => function ( WP_REST_Request $request ) use ( $operation ) {
						return WP_Plugin_Base_REST_Operations_Executor::execute( $operation, $request );
					},
					'permission_callback' => function ( WP_REST_Request $request ) use ( $plugin_slug, $operation ) {
						return WP_Plugin_Base_REST_Operations_Permissions::check_operation( $plugin_slug, $operation, $request );
					},
					'args'                => self::build_args( $operation ),
				)
			);
		}

		/**
		 * Builds route args from the operation input schema.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $operation Operation manifest.
		 * @return array<string,mixed>
		 */
		private static function build_args( array $operation ) {
			return WP_Plugin_Base_REST_Operations_Input::build_args( $operation );
		}

		/**
		 * Emits a developer-facing notice when an invalid manifest entry is skipped.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $operation Operation manifest.
		 * @return void
		 */
		private static function report_invalid_operation( array $operation ) {
			$operation_id = isset( $operation['id'] ) ? (string) $operation['id'] : '(unknown)';
			$message      = sprintf(
				/* translators: %s: operation id. */
				__( 'Skipped registering REST operation %s because its callback is missing or not callable.', '__PLUGIN_SLUG__' ),
				$operation_id
			);

			if ( function_exists( '_doing_it_wrong' ) ) {
				_doing_it_wrong( __METHOD__, esc_html( $message ), '1.6.0' );
				return;
			}

			// phpcs:ignore WordPress.PHP.DevelopmentFunctions.error_log_trigger_error -- Intentional fallback when _doing_it_wrong() is unavailable.
			trigger_error( esc_html( $message ), E_USER_WARNING );
		}
	}
}
