<?php
/**
 * REST operations registry.
 *
 * @package WPPluginBase
 * @since NEXT
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( ! class_exists( 'WP_Plugin_Base_REST_Operations_Registry' ) ) {
	/**
	 * Stores operation manifests declared by the child repository.
	 *
	 * @since NEXT
	 */
	class WP_Plugin_Base_REST_Operations_Registry {
		/**
		 * Registered operations keyed by id.
		 *
		 * @var array<string,array<string,mixed>>
		 */
		private static $operations = array();

		/**
		 * Registers a batch of operations.
		 *
		 * @since NEXT
		 *
		 * @param array<int,array<string,mixed>> $operations Operation manifests.
		 * @return void
		 */
		public static function register_many( array $operations ) {
			foreach ( $operations as $operation ) {
				self::register( $operation );
			}
		}

		/**
		 * Registers a single operation if it has a valid id.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $operation Operation manifest.
		 * @return void
		 */
		public static function register( array $operation ) {
			if ( empty( $operation['id'] ) || ! is_string( $operation['id'] ) ) {
				return;
			}

			self::$operations[ $operation['id'] ] = $operation;
		}

		/**
		 * Returns all registered operations.
		 *
		 * @since NEXT
		 *
		 * @return array<int,array<string,mixed>>
		 */
		public static function all() {
			return array_values( self::$operations );
		}

		/**
		 * Returns a UI-safe summary keyed by operation id.
		 *
		 * @since NEXT
		 *
		 * @return array<string,array<string,mixed>>
		 */
		public static function summary() {
			$summary = array();

			foreach ( self::$operations as $operation_id => $operation ) {
				$summary[ $operation_id ] = array(
					'route'      => isset( $operation['route'] ) ? (string) $operation['route'] : '',
					'methods'    => isset( $operation['methods'] ) ? $operation['methods'] : array(),
					'visibility' => isset( $operation['visibility'] ) ? (string) $operation['visibility'] : 'admin',
				);
			}

			return $summary;
		}
	}
}
