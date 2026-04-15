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
	}
}
