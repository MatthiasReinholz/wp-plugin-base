<?php
/**
 * Admin UI loader for managed app conventions.
 *
 * @package WPPluginBase
 * @since NEXT
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

if ( ! class_exists( 'WP_Plugin_Base_Admin_UI_Loader' ) ) {
	/**
	 * Registers and renders a standard admin application shell.
	 *
	 * @since NEXT
	 */
	class WP_Plugin_Base_Admin_UI_Loader {
		/**
		 * Page definitions keyed by hook suffix.
		 *
		 * @var array<string,array<string,mixed>>
		 */
		private static $pages = array();

		/**
		 * Registers an admin page and its asset hooks.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $config Page config.
		 * @return void
		 */
		public static function register_page( array $config ) {
			add_action(
				'admin_menu',
				static function () use ( $config ) {
					$hook_suffix = add_menu_page(
						$config['page_title'],
						$config['menu_title'],
						$config['capability'],
						$config['menu_slug'],
						static function () use ( $config ) {
							if ( ! current_user_can( $config['capability'] ) ) {
								return;
							}

							self::render_root( $config );
						},
						'dashicons-admin-generic',
						58
					);

					if ( is_string( $hook_suffix ) && '' !== $hook_suffix ) {
						self::$pages[ $hook_suffix ] = $config;
					}
				}
			);

			add_action(
				'admin_enqueue_scripts',
				static function ( $hook_suffix ) {
					if ( empty( self::$pages[ $hook_suffix ] ) ) {
						return;
					}

					self::enqueue_assets( self::$pages[ $hook_suffix ] );
				}
			);
		}

		/**
		 * Renders the app root.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $config Page config.
		 * @return void
		 */
		private static function render_root( array $config ) {
			echo '<div class="wrap">';
			echo '<div id="' . esc_attr( $config['root_id'] ) . '"></div>';
			echo '</div>';
		}

		/**
		 * Enqueues built UI assets.
		 *
		 * @since NEXT
		 *
		 * @param array<string,mixed> $config Page config.
		 * @return void
		 */
		private static function enqueue_assets( array $config ) {
			$asset_base = dirname( __DIR__, 3 ) . '/assets/admin-ui';
			$asset_file = $asset_base . '/index.asset.php';
			$script_url = plugins_url( 'assets/admin-ui/index.js', dirname( __DIR__, 3 ) . '/__MAIN_PLUGIN_FILE__' );
			$style_url  = plugins_url( 'assets/admin-ui/style-index.css', dirname( __DIR__, 3 ) . '/__MAIN_PLUGIN_FILE__' );

			$asset_data = file_exists( $asset_file )
				? require $asset_file
				: array(
					'dependencies' => array( 'wp-api-fetch', 'wp-components', 'wp-element', 'wp-i18n' ),
					'version'      => file_exists( dirname( __DIR__, 3 ) . '/assets/admin-ui/index.js' ) ? (string) filemtime( dirname( __DIR__, 3 ) . '/assets/admin-ui/index.js' ) : '1',
				);

			wp_enqueue_script(
				$config['script_handle'],
				$script_url,
				$asset_data['dependencies'],
				$asset_data['version'],
				true
			);

			if ( function_exists( 'wp_set_script_translations' ) && ! empty( $config['text_domain'] ) ) {
				wp_set_script_translations(
					$config['script_handle'],
					$config['text_domain'],
					dirname( __DIR__, 3 ) . '/languages'
				);
			}

			if ( file_exists( $asset_base . '/style-index.css' ) ) {
				wp_enqueue_style(
					$config['style_handle'],
					$style_url,
					array( 'wp-components' ),
					$asset_data['version']
				);
			}

			wp_add_inline_script(
				$config['script_handle'],
				'window.wpPluginBaseAdminUi = window.wpPluginBaseAdminUi || {}; window.wpPluginBaseAdminUi[' . wp_json_encode( $config['plugin_slug'] ) . '] = ' . wp_json_encode(
					array(
						'pluginSlug'            => $config['plugin_slug'],
						'restNamespace'         => $config['rest_namespace'],
						'rootId'                => $config['root_id'],
						'pluginName'            => $config['plugin_name'],
						'experimentalDataViews' => ! empty( $config['experimental_dataviews'] ),
						'operations'            => class_exists( 'WP_Plugin_Base_REST_Operations_Registry' ) ? WP_Plugin_Base_REST_Operations_Registry::summary() : array(),
					)
				),
				'before'
			);
		}
	}
}
