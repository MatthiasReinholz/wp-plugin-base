<?php
/**
 * Managed by wp-plugin-base. Do not edit manually.
 *
 * Initializes Plugin Update Checker (PUC) so this plugin can receive updates
 * from the configured runtime update provider in the built-in WordPress update UI.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

$wp_plugin_base_runtime_updater_should_bootstrap = (
	( function_exists( 'is_admin' ) && is_admin() )
	|| ( function_exists( 'wp_doing_cron' ) && wp_doing_cron() )
	|| ( defined( 'DOING_CRON' ) && DOING_CRON )
	|| ( defined( 'WP_CLI' ) && WP_CLI )
);

if ( function_exists( 'apply_filters' ) ) {
	$wp_plugin_base_runtime_updater_should_bootstrap = (bool) apply_filters(
		'__PLUGIN_SLUG___runtime_updater_should_bootstrap',
		$wp_plugin_base_runtime_updater_should_bootstrap
	);
}

if ( ! $wp_plugin_base_runtime_updater_should_bootstrap ) {
	return;
}

$wp_plugin_base_puc_bootstrap = __DIR__ . '/plugin-update-checker/plugin-update-checker.php';
if ( ! file_exists( $wp_plugin_base_puc_bootstrap ) ) {
	return;
}

require_once $wp_plugin_base_puc_bootstrap;

if ( ! class_exists( '\\YahnisElsts\\PluginUpdateChecker\\v5\\PucFactory' ) ) {
	return;
}

$wp_plugin_base_runtime_updater_main_file  = dirname( dirname( __DIR__ ) ) . '/__MAIN_PLUGIN_FILE__';
$wp_plugin_base_runtime_updater_source_url = '__PLUGIN_RUNTIME_UPDATE_SOURCE_URL__';
$wp_plugin_base_runtime_updater_provider   = '__PLUGIN_RUNTIME_UPDATE_PROVIDER__';
$wp_plugin_base_runtime_updater_slug       = '__PLUGIN_SLUG__';

if (
	file_exists( $wp_plugin_base_runtime_updater_main_file )
	&& '' !== $wp_plugin_base_runtime_updater_source_url
	&& 'none' !== $wp_plugin_base_runtime_updater_provider
) {
	$wp_plugin_base_runtime_updater = \YahnisElsts\PluginUpdateChecker\v5\PucFactory::buildUpdateChecker(
		$wp_plugin_base_runtime_updater_source_url,
		$wp_plugin_base_runtime_updater_main_file,
		$wp_plugin_base_runtime_updater_slug
	);

	if (
		method_exists( $wp_plugin_base_runtime_updater, 'getVcsApi' )
		&& in_array( $wp_plugin_base_runtime_updater_provider, array( 'github-release', 'gitlab-release' ), true )
	) {
		$wp_plugin_base_runtime_updater->getVcsApi()->enableReleaseAssets( '/\\.zip($|[?&#])/i' );
	}
}
