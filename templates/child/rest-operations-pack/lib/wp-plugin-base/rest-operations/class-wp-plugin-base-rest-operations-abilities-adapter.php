<?php
/**
 * Abilities adapter for REST operations.
 *
 * @package WPPluginBase
 * @since NEXT
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( ! class_exists( 'WP_Plugin_Base_REST_Operations_Abilities_Adapter' ) ) {
	/**
	 * Registers abilities for operations when the Abilities API is available.
	 *
	 * @since NEXT
	 */
	class WP_Plugin_Base_REST_Operations_Abilities_Adapter {
		/**
		 * Registers the plugin ability category.
		 *
		 * @since NEXT
		 *
		 * @param string $category_slug  Category slug.
		 * @param string $category_label Category label.
		 * @return void
		 */
		public static function register_category( $category_slug, $category_label ) {
			if ( ! function_exists( 'wp_register_ability_category' ) ) {
				return;
			}

			wp_register_ability_category(
				$category_slug,
				array(
					'label'       => $category_label,
					'description' => sprintf(
						/* translators: %s: plugin label. */
						__( 'Abilities exposed by %s.', '__PLUGIN_SLUG__' ),
						$category_label
					),
				)
			);
		}

		/**
		 * Registers abilities for the operation set.
		 *
		 * @since NEXT
		 *
		 * @param string                         $plugin_slug   Plugin slug.
		 * @param string                         $category_slug Category slug.
		 * @param array<int,array<string,mixed>> $operations Operations.
		 * @return void
		 */
		public static function register_operations( $plugin_slug, $category_slug, array $operations ) {
			if ( ! function_exists( 'wp_register_ability' ) ) {
				return;
			}

			foreach ( $operations as $operation ) {
				self::register_operation( $plugin_slug, $category_slug, $operation );
			}
		}

		/**
		 * Registers a single ability.
		 *
		 * @since NEXT
		 *
		 * @param string              $plugin_slug   Plugin slug.
		 * @param string              $category_slug Category slug.
		 * @param array<string,mixed> $operation     Operation manifest.
		 * @return void
		 */
		private static function register_operation( $plugin_slug, $category_slug, array $operation ) {
			if ( empty( $operation['callback'] ) || ! is_callable( $operation['callback'] ) ) {
				return;
			}

			$ability = isset( $operation['ability'] ) && is_array( $operation['ability'] ) ? $operation['ability'] : array();
			$name    = ! empty( $ability['name'] ) ? $ability['name'] : $plugin_slug . '/' . str_replace( '.', '-', $operation['id'] );
			$label   = ! empty( $ability['label'] ) ? $ability['label'] : ucwords( str_replace( array( '.', '-' ), ' ', $operation['id'] ) );
			$args    = array(
				'label'            => $label,
				'description'      => ! empty( $ability['description'] ) ? $ability['description'] : sprintf(
					/* translators: %s: operation id. */
					__( 'Executes the %s operation.', '__PLUGIN_SLUG__' ),
					$operation['id']
				),
				'category'         => $category_slug,
				'output_schema'    => ! empty( $operation['output_schema'] ) ? $operation['output_schema'] : array(
					'type'       => 'object',
					'properties' => array(),
				),
				'execute_callback' => function ( $input = null ) use ( $plugin_slug, $operation ) {
					$request = new WP_REST_Request(
						is_array( $operation['methods'] ) ? reset( $operation['methods'] ) : $operation['methods'],
						$operation['route']
					);
					$prepared_input = WP_Plugin_Base_REST_Operations_Input::prepare_input( $operation, $input );
					if ( is_wp_error( $prepared_input ) ) {
						return $prepared_input;
					}

					if ( is_array( $prepared_input ) ) {
						$request->set_params( $prepared_input );
					}

					$permission = WP_Plugin_Base_REST_Operations_Permissions::check_operation( $plugin_slug, $operation, $request );
					if ( is_wp_error( $permission ) ) {
						return $permission;
					}

					return WP_Plugin_Base_REST_Operations_Responses::unwrap(
						WP_Plugin_Base_REST_Operations_Executor::execute( $operation, $request )
					);
				},
				'show_in_rest'     => ! empty( $ability['show_in_rest'] ),
				'annotations'      => ! empty( $operation['annotations'] ) && is_array( $operation['annotations'] ) ? $operation['annotations'] : array(),
			);

			if ( ! empty( $operation['input_schema'] ) ) {
				$args['input_schema'] = $operation['input_schema'];
			}

			wp_register_ability( $name, $args );
		}
	}
}
