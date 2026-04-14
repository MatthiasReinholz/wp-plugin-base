<?php
/**
 * Managed by wp-plugin-base. Do not edit manually.
 *
 * Initializes Plugin Update Checker (PUC) so this plugin can receive updates
 * from GitHub Releases in the built-in WordPress update UI.
 *
 * @package WPPluginBase
 * @since NEXT
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

$wp_plugin_base_puc_bootstrap = __DIR__ . '/plugin-update-checker/plugin-update-checker.php';
if ( ! file_exists( $wp_plugin_base_puc_bootstrap ) ) {
	return;
}

require_once $wp_plugin_base_puc_bootstrap;

if ( ! class_exists( '\\YahnisElsts\\PluginUpdateChecker\\v5\\PucFactory' ) ) {
	return;
}

$wp_plugin_base_github_updater_main_file = dirname( dirname( __DIR__ ) ) . '/__MAIN_PLUGIN_FILE__';
$wp_plugin_base_github_updater_repo_url  = '__GITHUB_RELEASE_UPDATER_REPO_URL__';
$wp_plugin_base_github_updater_slug      = '__PLUGIN_SLUG__';

if (
	file_exists( $wp_plugin_base_github_updater_main_file )
	&& '' !== $wp_plugin_base_github_updater_repo_url
) {
	$wp_plugin_base_github_updater = \YahnisElsts\PluginUpdateChecker\v5\PucFactory::buildUpdateChecker(
		$wp_plugin_base_github_updater_repo_url,
		$wp_plugin_base_github_updater_main_file,
		$wp_plugin_base_github_updater_slug
	);

	if ( method_exists( $wp_plugin_base_github_updater, 'getVcsApi' ) ) {
		$wp_plugin_base_github_updater->getVcsApi()->enableReleaseAssets( '/\\.zip($|[?&#])/i' );
	}
}
