<?php
/**
 * REST adapter for operation manifests.
 *
 * @package WPPluginBase
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( ! class_exists( 'WP_Plugin_Base_REST_Operations_REST_Adapter' ) ) {
	/**
	 * Registers REST routes from operation manifests.
	 */
	class WP_Plugin_Base_REST_Operations_REST_Adapter {
		/**
		 * Registers all operations with the REST API.
		 *
		 * @param string                    $plugin_slug Plugin slug.
		 * @param string                    $namespace REST namespace.
		 * @param array<int,array<string,mixed>> $operations Operations.
		 * @return void
		 */
		public static function register_all( $plugin_slug, $namespace, array $operations ) {
			foreach ( $operations as $operation ) {
				self::register_operation( $plugin_slug, $namespace, $operation );
			}
		}

		/**
		 * Registers a single operation.
		 *
		 * @param string             $plugin_slug Plugin slug.
		 * @param string             $namespace REST namespace.
		 * @param array<string,mixed> $operation Operation manifest.
		 * @return void
		 */
		private static function register_operation( $plugin_slug, $namespace, array $operation ) {
			if ( empty( $operation['route'] ) || empty( $operation['callback'] ) || ! is_callable( $operation['callback'] ) ) {
				self::report_invalid_operation( $operation );
				return;
			}

			register_rest_route(
				$namespace,
				$operation['route'],
				array(
					'methods'             => $operation['methods'],
					'callback'            => function( WP_REST_Request $request ) use ( $operation ) {
						return WP_Plugin_Base_REST_Operations_Executor::execute( $operation, $request );
					},
					'permission_callback' => function( WP_REST_Request $request ) use ( $plugin_slug, $operation ) {
						return WP_Plugin_Base_REST_Operations_Permissions::check_operation( $plugin_slug, $operation, $request );
					},
					'args'                => self::build_args( $operation ),
				)
			);
		}

		/**
		 * Builds route args from the operation input schema.
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

			trigger_error( $message, E_USER_WARNING );
		}
	}
}
