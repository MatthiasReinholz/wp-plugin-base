<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

final class WpPluginBaseBootstrapTest extends TestCase
{
	public function test_bootstrap_defines_abspath_context(): void
	{
		$this->assertTrue(defined('ABSPATH'));
		$this->assertNotSame('', ABSPATH);
	}

	public function test_bootstrap_loads_main_plugin_file(): void
	{
		$pluginFile = realpath(dirname(__DIR__, 2) . '/__MAIN_PLUGIN_FILE__');
		$includedFiles = array_map(
			static function (string $path): string {
				$resolved = realpath($path);
				return false === $resolved ? $path : $resolved;
			},
			get_included_files()
		);

		$this->assertNotFalse($pluginFile);
		$this->assertContains($pluginFile, $includedFiles);
	}
}
