<?php
declare(strict_types=1);

/**
 * Child-owned PHPUnit bootstrap overlay.
 *
 * This file is loaded from tests/bootstrap.php before the managed plugin load
 * hook runs. In WP test mode it is loaded after includes/functions.php, so
 * tests_add_filter() and similar helpers are available for repo-specific test
 * hooks or optional integration bootstrap code. The managed bootstrap scope
 * exposes $plugin_file and $tests_dir when you need them.
 */
