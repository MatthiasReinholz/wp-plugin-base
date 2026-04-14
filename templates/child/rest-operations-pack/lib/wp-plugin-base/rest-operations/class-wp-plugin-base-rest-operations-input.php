<?php
/**
 * REST operation input-schema helpers.
 *
 * @package WPPluginBase
 * @since NEXT
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( ! class_exists( 'WP_Plugin_Base_REST_Operations_Input' ) ) {
	/**
	 * Normalizes schema-backed input handling across transports.
	 *
	 * @since NEXT
	 */
	class WP_Plugin_Base_REST_Operations_Input {
		/**
		 * Builds REST route arg definitions from an operation schema.
		 *
		 * WordPress does not promote object-level `required` declarations down to
		 * the per-field arg map returned by `rest_get_endpoint_args_for_schema()`,
		 * so apply them explicitly here.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $operation Operation manifest.
		 * @return array<string,mixed>
		 */
		public static function build_args( array $operation ) {
			if ( empty( $operation['input_schema'] ) || ! is_array( $operation['input_schema'] ) ) {
				return array();
			}

			if ( ! function_exists( 'rest_get_endpoint_args_for_schema' ) ) {
				return array();
			}

			$args     = rest_get_endpoint_args_for_schema( $operation['input_schema'] );
			$required = isset( $operation['input_schema']['required'] ) && is_array( $operation['input_schema']['required'] )
				? $operation['input_schema']['required']
				: array();

			foreach ( $required as $property_name ) {
				if ( isset( $args[ $property_name ] ) && is_array( $args[ $property_name ] ) ) {
					$args[ $property_name ]['required'] = true;
				}
			}

			return $args;
		}

		/**
		 * Validates and sanitizes non-REST input against the declared schema.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $operation Operation manifest.
		 * @param mixed               $input Raw input payload.
		 * @return array<string,mixed>|WP_Error
		 */
		public static function prepare_input( array $operation, $input ) {
			$prepared_input = is_array( $input ) ? $input : array();

			if ( empty( $operation['input_schema'] ) || ! is_array( $operation['input_schema'] ) ) {
				return $prepared_input;
			}

			$schema = $operation['input_schema'];

			if ( function_exists( 'rest_validate_value_from_schema' ) ) {
				$validation = rest_validate_value_from_schema( $prepared_input, $schema, 'input' );
				if ( is_wp_error( $validation ) ) {
					return $validation;
				}
			}

			if ( function_exists( 'rest_sanitize_value_from_schema' ) ) {
				$prepared_input = rest_sanitize_value_from_schema( $prepared_input, $schema, 'input' );
			}

			return is_array( $prepared_input ) ? $prepared_input : array();
		}
	}
}
