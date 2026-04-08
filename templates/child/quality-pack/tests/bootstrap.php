<?php
declare(strict_types=1);

$plugin_file = dirname(__DIR__) . '/__MAIN_PLUGIN_FILE__';

if (! file_exists($plugin_file)) {
	fwrite(STDERR, "Main plugin file not found: {$plugin_file}\n");
	exit(1);
}

$tests_dir = getenv('WP_TESTS_DIR');

if ($tests_dir && file_exists($tests_dir . '/includes/functions.php')) {
	require_once $tests_dir . '/includes/functions.php';

	tests_add_filter(
		'muplugins_loaded',
		static function () use ($plugin_file): void {
			require $plugin_file;
		}
	);

	require $tests_dir . '/includes/bootstrap.php';
	return;
}

if (! defined('ABSPATH')) {
	define('ABSPATH', dirname(__DIR__) . '/');
}

require_once $plugin_file;
