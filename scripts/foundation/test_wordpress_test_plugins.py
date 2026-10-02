#!/usr/bin/env python3
"""Check exact dependency pins and the actual Plugin Check wp-env configuration."""
import json
import os
import shutil
import tempfile
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'scripts/lib/wordpress_test_plugins.php'


class WordPressTestPlugins(unittest.TestCase):
    def run_helper(self, value, *args):
        return subprocess.run(['php', str(HELPER), value, *args], capture_output=True, text=True, check=False)

    def test_no_dependencies_preserves_child(self):
        result = self.run_helper('', '/tmp/child plugin', '20123', '30123')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {
            'plugins': ['/tmp/child plugin'], 'port': 20123,
            'testsPort': 30123, 'testsEnvironment': False,
        })

    def test_pinned_dependencies_precede_child(self):
        result = self.run_helper('woocommerce@11.1.2,contact-form-7@6.1', '/tmp/child', '20001', '30001')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['plugins'], [
            'https://downloads.wordpress.org/plugin/woocommerce.11.1.2.zip',
            'https://downloads.wordpress.org/plugin/contact-form-7.6.1.zip', '/tmp/child',
        ])

    def test_config_loader_and_validator_share_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            shutil.copytree(ROOT / 'tests/fixtures/standard-plugin', directory, dirs_exist_ok=True)
            config = Path(directory) / '.wp-plugin-base.env'
            original = config.read_text()
            for value, expected in [('woocommerce@11.1.2', 0), ('woocommerce@latest', 1)]:
                config.write_text(original + '\nWORDPRESS_TEST_PLUGINS=' + value + '\n')
                env = dict(os.environ, WP_PLUGIN_BASE_ROOT=directory)
                env.pop('WORDPRESS_TEST_PLUGINS', None)
                result = subprocess.run(['bash', str(ROOT / 'scripts/ci/validate_config.sh')],
                                        env=env, capture_output=True, text=True, check=False)
                if expected == 0:
                    self.assertEqual(result.returncode, 0, result.stderr)
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('WORDPRESS_TEST_PLUGINS', result.stderr)

    def test_rejects_unpinned_or_unsafe_sources(self):
        for value in ['woocommerce', 'woocommerce@latest', 'woocommerce@11',
                      'woocommerce@^11.1', 'woocommerce@11.1-beta',
                      'https://evil.test/plugin.zip', '../woo@11.1',
                      'woo@11.1,', ' woo@11.1', 'woo@11.1\n',
                      'woo@11.1,woo@11.2', 'Woo@11.1',
                      'woo@11.1?token=secret', 'woo@11.1, bar@1.2']:
            with self.subTest(value=value):
                result = self.run_helper(value)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('WORDPRESS_TEST_PLUGINS', result.stderr)
                self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()
