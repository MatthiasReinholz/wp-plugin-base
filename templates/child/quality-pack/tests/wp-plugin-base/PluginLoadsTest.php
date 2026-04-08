<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

final class WpPluginBasePluginLoadsTest extends TestCase
{
	public function test_main_plugin_file_exists(): void
	{
		$this->assertFileExists(dirname(__DIR__, 2) . '/__MAIN_PLUGIN_FILE__');
	}
}
