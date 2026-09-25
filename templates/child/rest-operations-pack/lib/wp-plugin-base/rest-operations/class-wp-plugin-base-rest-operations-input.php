<?php // phpcs:disable WordPress.Files.FileName.InvalidClassFileName -- Runtime class prefixes vary by consumer; managed filenames remain stable.
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
		 * Complete-object validation enforces required property presence. The REST
		 * per-field required flag also rejects explicit null, which is different
		 * from a required property whose schema permits null.
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

			$args = rest_get_endpoint_args_for_schema( $operation['input_schema'] );

			// Defaults are applied only after whole-object validation in both transports.
			foreach ( $args as &$argument ) {
				unset( $argument['default'], $argument['required'] );
			}
			unset( $argument );

			return $args;
		}

		/**
		 * Validates and sanitizes operation input against the declared schema.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $operation Operation manifest.
		 * @param mixed               $input Raw input payload.
		 * @return array<string,mixed>|WP_Error
		 */
		public static function prepare_input( array $operation, $input ) {
			$prepared_input = is_object( $input ) ? get_object_vars( $input ) : $input;

			if ( empty( $operation['input_schema'] ) || ! is_array( $operation['input_schema'] ) ) {
				return is_array( $prepared_input ) ? $prepared_input : array();
			}

			$schema = $operation['input_schema'];

			if ( function_exists( 'rest_validate_value_from_schema' ) ) {
				$validation = rest_validate_value_from_schema( $prepared_input, $schema, 'input' );
				if ( is_wp_error( $validation ) ) {
					return $validation;
				}
			}

			// JSON Schema defaults do not satisfy required properties. Core Abilities
			// validates the raw payload before invoking either adapter callback.
			if ( is_array( $prepared_input ) && ! empty( $schema['properties'] ) ) {
				foreach ( $schema['properties'] as $name => $property ) {
					if ( ! array_key_exists( $name, $prepared_input ) && array_key_exists( 'default', $property ) ) {
						$prepared_input[ $name ] = $property['default'];
					}
				}
			}

			if ( function_exists( 'rest_sanitize_value_from_schema' ) ) {
				$prepared_input = rest_sanitize_value_from_schema( $prepared_input, $schema, 'input' );
			}

			if ( is_wp_error( $prepared_input ) ) {
				return $prepared_input;
			}

			// Sanitizers and configured defaults can change schema-constrained values.
			// Both transports must validate the final payload before permissions run.
			if ( function_exists( 'rest_validate_value_from_schema' ) ) {
				$validation = rest_validate_value_from_schema( $prepared_input, $schema, 'input' );
				if ( is_wp_error( $validation ) ) {
					return $validation;
				}
			}

			return is_array( $prepared_input ) ? $prepared_input : array();
		}

		/**
		 * Validates the complete REST payload, excluding undeclared transport controls.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $operation Operation manifest.
		 * @param WP_REST_Request     $request Request instance.
		 * @return WP_REST_Request|WP_Error
		 */
		public static function prepare_rest_request( array $operation, WP_REST_Request $request ) {
			if ( empty( $operation['input_schema'] ) ) {
				return $request;
			}

			$input      = $request->get_params();
			$properties = isset( $operation['input_schema']['properties'] ) ? $operation['input_schema']['properties'] : array();
			foreach ( array( '_fields', '_embed', '_envelope', '_locale', '_method', '_jsonp', '_wpnonce', 'rest_route' ) as $control ) {
				if ( ! array_key_exists( $control, $properties ) ) {
					unset( $input[ $control ] );
				}
			}

			$prepared_input = self::prepare_input( $operation, $input );
			if ( is_wp_error( $prepared_input ) ) {
				$data           = $prepared_input->get_error_data();
				$data           = is_array( $data ) ? $data : array();
				$data['status'] = 400;
				$prepared_input->add_data( $data );
				return $prepared_input;
			}

			foreach ( $prepared_input as $key => $value ) {
				$request->set_param( $key, $value );
			}

			return $request;
		}
	}
}
