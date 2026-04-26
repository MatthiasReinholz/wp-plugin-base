<?php
/**
 * REST operation authorization helpers.
 *
 * @package WPPluginBase
 * @since NEXT
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( ! class_exists( 'WP_Plugin_Base_REST_Operations_Permissions' ) ) {
	/**
	 * Evaluates capability and scope constraints for operations.
	 *
	 * @since NEXT
	 */
	class WP_Plugin_Base_REST_Operations_Permissions {
		/**
		 * Checks whether the current request may execute the operation.
		 *
		 * @since NEXT
		 *
		 * @param string              $plugin_slug Plugin slug.
		 * @param array<string,mixed> $operation Operation manifest.
		 * @param WP_REST_Request     $request     Request instance.
		 * @return true|WP_Error
		 */
		public static function check_operation( $plugin_slug, array $operation, WP_REST_Request $request ) {
			$visibility = isset( $operation['visibility'] ) ? (string) $operation['visibility'] : 'admin';

			if ( 'public' === $visibility ) {
				return true;
			}

			if ( ! is_user_logged_in() ) {
				return new WP_Error(
					'wp_plugin_base_rest_authentication_required',
					__( 'Authentication is required for this operation.', '__PLUGIN_SLUG__' ),
					array( 'status' => 401 )
				);
			}

			$capability_check = self::check_capability( $operation, $request );
			if ( is_wp_error( $capability_check ) ) {
				return $capability_check;
			}

			$scope_check = self::check_scopes( $plugin_slug, $operation, $request );
			if ( is_wp_error( $scope_check ) ) {
				return $scope_check;
			}

			return true;
		}

		/**
		 * Validates capability requirements.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $operation Operation manifest.
		 * @param WP_REST_Request     $request   Request instance.
		 * @return true|WP_Error
		 */
		private static function check_capability( array $operation, WP_REST_Request $request ) {
			if ( ! empty( $operation['capability_callback'] ) && is_callable( $operation['capability_callback'] ) ) {
				try {
					$result = call_user_func( $operation['capability_callback'], $request, $operation );
				} catch ( Throwable $error ) {
					self::log_capability_failure( $operation, $error );

					return new WP_Error(
						'wp_plugin_base_rest_capability_check_failed',
						__( 'The REST operation permission callback failed.', '__PLUGIN_SLUG__' ),
						array( 'status' => 500 )
					);
				}

				if ( is_wp_error( $result ) ) {
					return $result;
				}

				if ( true === $result ) {
					return true;
				}

				return new WP_Error(
					'wp_plugin_base_rest_forbidden',
					__( 'You are not allowed to execute this operation.', '__PLUGIN_SLUG__' ),
					array( 'status' => 403 )
				);
			}

			$capabilities = isset( $operation['capability'] ) ? $operation['capability'] : array();
			if ( is_string( $capabilities ) ) {
				$capabilities = array( $capabilities );
			}

			if ( empty( $capabilities ) ) {
				return new WP_Error(
					'wp_plugin_base_rest_forbidden',
					__( 'You are not allowed to execute this operation.', '__PLUGIN_SLUG__' ),
					array( 'status' => 403 )
				);
			}

			foreach ( $capabilities as $capability ) {
				if ( ! current_user_can( $capability ) ) {
					return new WP_Error(
						'wp_plugin_base_rest_forbidden',
						__( 'You are not allowed to execute this operation.', '__PLUGIN_SLUG__' ),
						array( 'status' => 403 )
					);
				}
			}

			return true;
		}

		/**
		 * Logs uncaught capability callback failures for developer visibility.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $operation Operation manifest.
		 * @param Throwable           $error     Thrown error.
		 * @return void
		 */
		private static function log_capability_failure( array $operation, Throwable $error ) {
			$operation_id = isset( $operation['id'] ) ? (string) $operation['id'] : '(unknown)';
			$error_class  = get_class( $error );
			$message      = sprintf(
				/* translators: 1: operation id, 2: thrown exception class name. */
				__( 'REST operation %1$s capability_callback threw an uncaught %2$s.', '__PLUGIN_SLUG__' ),
				$operation_id,
				$error_class
			);

			// phpcs:ignore WordPress.PHP.DevelopmentFunctions.error_log_error_log -- Intentional runtime logging for uncaught permission callback exceptions.
			error_log( $message );
		}

		/**
		 * Validates scope requirements after capability checks succeed.
		 *
		 * @since NEXT
		 *
		 * @param string              $plugin_slug Plugin slug.
		 * @param array<string,mixed> $operation   Operation manifest.
		 * @param WP_REST_Request     $request     Request instance.
		 * @return true|WP_Error
		 */
		private static function check_scopes( $plugin_slug, array $operation, WP_REST_Request $request ) {
			$required_scopes = isset( $operation['required_scopes'] ) ? $operation['required_scopes'] : array();
			if ( ! is_array( $required_scopes ) ) {
				return self::invalid_scope_configuration_error();
			}

			if ( empty( $required_scopes ) ) {
				return true;
			}

			$granted_scopes = self::granted_scopes( $plugin_slug, $operation, $request );
			if ( is_wp_error( $granted_scopes ) ) {
				return $granted_scopes;
			}

			foreach ( $required_scopes as $required_scope ) {
				if ( ! is_string( $required_scope ) || '' === $required_scope ) {
					return self::invalid_scope_configuration_error();
				}

				if ( ! self::has_scope( $required_scope, $granted_scopes ) ) {
					return new WP_Error(
						'wp_plugin_base_rest_scope_forbidden',
						__( 'You do not have the required operation scope.', '__PLUGIN_SLUG__' ),
						array( 'status' => 403 )
					);
				}
			}

			return true;
		}

		/**
		 * Resolves granted scopes for the current user/request.
		 *
		 * @since NEXT
		 *
		 * @param string              $plugin_slug Plugin slug.
		 * @param array<string,mixed> $operation   Operation manifest.
		 * @param WP_REST_Request     $request     Request instance.
		 * @return array<int,string>|WP_Error
		 */
		private static function granted_scopes( $plugin_slug, array $operation, WP_REST_Request $request ) {
			$granted_scopes = array();
			$scope_key      = str_replace( '-', '_', $plugin_slug ) . '_rest_operation_scopes';

			if ( current_user_can( 'manage_options' ) ) {
				$granted_scopes[] = '*';
			}

			$option_scopes = get_option( $scope_key, array() );
			if ( is_array( $option_scopes ) ) {
				$granted_scopes = array_merge( $granted_scopes, self::normalize_scopes( $option_scopes ) );
			}

			$user_scopes = get_user_meta( get_current_user_id(), $scope_key, true );
			if ( is_array( $user_scopes ) ) {
				$granted_scopes = array_merge( $granted_scopes, self::normalize_scopes( $user_scopes ) );
			}

			try {
				$filtered_scopes = apply_filters(
					$plugin_slug . '_rest_granted_scopes',
					$granted_scopes,
					$operation,
					$request
				);
			} catch ( Throwable $error ) {
				return new WP_Error(
					'wp_plugin_base_rest_scope_check_failed',
					__( 'The REST operation scope filter failed.', '__PLUGIN_SLUG__' ),
					array( 'status' => 500 )
				);
			}

			if ( ! is_array( $filtered_scopes ) ) {
				return new WP_Error(
					'wp_plugin_base_rest_scope_check_failed',
					__( 'The REST operation scope filter returned invalid data.', '__PLUGIN_SLUG__' ),
					array( 'status' => 500 )
				);
			}

			return array_values( array_unique( self::normalize_scopes( $filtered_scopes ) ) );
		}

		/**
		 * Normalizes scope declarations into a flat string list.
		 *
		 * @since NEXT
		 *
		 * @param mixed $raw_scopes Raw scope declaration.
		 * @return array<int,string>
		 */
		private static function normalize_scopes( $raw_scopes ) {
			$normalized = array();

			if ( is_string( $raw_scopes ) && '' !== $raw_scopes ) {
				return array( $raw_scopes );
			}

			if ( ! is_array( $raw_scopes ) ) {
				return $normalized;
			}

			foreach ( $raw_scopes as $key => $value ) {
				if ( is_int( $key ) ) {
					if ( is_string( $value ) && '' !== $value ) {
						$normalized[] = $value;
					}
					continue;
				}

				if ( 'allow' === $key && is_array( $value ) ) {
					$normalized = array_merge( $normalized, self::normalize_scopes( $value ) );
				}
			}

			return array_values( array_unique( $normalized ) );
		}

		/**
		 * Checks whether a required scope is granted by a scope list.
		 *
		 * @since NEXT
		 *
		 * @param string            $required_scope Required scope.
		 * @param array<int,string> $granted_scopes Granted scopes.
		 * @return bool
		 */
		private static function has_scope( $required_scope, array $granted_scopes ) {
			foreach ( $granted_scopes as $granted_scope ) {
				if ( '*' === $granted_scope || $required_scope === $granted_scope ) {
					return true;
				}

				$has_wildcard_suffix = function_exists( 'str_ends_with' )
					? str_ends_with( $granted_scope, '.*' )
					: substr( $granted_scope, -2 ) === '.*';
				if ( $has_wildcard_suffix ) {
					$prefix = substr( $granted_scope, 0, -2 );
					if ( '' !== $prefix && 0 === strpos( $required_scope, $prefix . '.' ) ) {
						return true;
					}
				}
			}

			return false;
		}

		/**
		 * Returns the fail-closed error for malformed operation scope metadata.
		 *
		 * @since NEXT
		 *
		 * @return WP_Error
		 */
		private static function invalid_scope_configuration_error() {
			return new WP_Error(
				'wp_plugin_base_rest_invalid_scope_configuration',
				__( 'The REST operation scope configuration is invalid.', '__PLUGIN_SLUG__' ),
				array( 'status' => 500 )
			);
		}
	}
}
