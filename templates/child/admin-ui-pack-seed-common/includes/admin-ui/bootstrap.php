<?php
/**
 * Child-owned admin UI bootstrap.
 *
 * @package __PLUGIN_SLUG__
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

WP_Plugin_Base_Admin_UI_Loader::register_page(
	array(
		'page_title'             => '__PLUGIN_NAME__',
		'menu_title'             => '__PLUGIN_NAME__',
		'capability'             => 'manage_options',
		'menu_slug'              => '__PLUGIN_SLUG__-admin-ui',
		'root_id'                => '__PLUGIN_SLUG__-admin-ui-root',
		'plugin_slug'            => '__PLUGIN_SLUG__',
		'text_domain'            => '__PLUGIN_SLUG__',
		'script_handle'          => '__PLUGIN_SLUG__-admin-ui',
		'style_handle'           => '__PLUGIN_SLUG__-admin-ui',
		'rest_namespace'         => '__REST_API_NAMESPACE__',
		'plugin_name'            => '__PLUGIN_NAME__',
		'experimental_dataviews' => 'true' === '__ADMIN_UI_EXPERIMENTAL_DATAVIEWS__',
	)
);
