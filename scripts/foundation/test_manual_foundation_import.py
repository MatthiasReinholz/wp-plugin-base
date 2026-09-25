#!/usr/bin/env python3
"""Manual import contract tests; fixture signatures never replace real release checks."""

import argparse
from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('foundation_import', ROOT / 'scripts/update/import_foundation_release.py')
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)


class ManualImport(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        self.project = self.root / 'project'
        self.project.mkdir()
        self.destination = self.project / '.wp-plugin-base'
        self.destination.mkdir(mode=0o750)
        (self.destination / 'owned').write_text('previous tree')
        (self.destination / 'owned').chmod(0o751)
        (self.project / '.wp-plugin-base.env').write_text('FOUNDATION_VERSION=v0.0.1\n')
        self.git('init', '-q', str(self.source))
        self.git('-C', str(self.source), 'config', 'user.email', 'fixture@example.invalid')
        self.git('-C', str(self.source), 'config', 'user.name', 'Fixture')
        (self.source / '.gitattributes').write_text('/templates export-ignore\n')
        for index in range(14):
            target = self.source / 'templates/child' / f'required-{index}.txt'
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(f'required template {index}\n')
        (self.source / 'script.sh').write_text('#!/bin/sh\nexit 0\n')
        (self.source / 'script.sh').chmod(0o755)
        self.commit = self.commit_source()
        self.git('-C', str(self.source), 'tag', 'v1.9.0')
        self.options = argparse.Namespace(version='v1.9.0', project_root=str(self.project),
                                          expected_commit=self.commit,
                                          source_provider='github-release',
                                          source_reference='example/foundation',
                                          source_api_base='https://api.github.com',
                                          source_sigstore_issuer='')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        actual_git = shutil.which('git')
        fake_git = self.bin / 'git'
        fake_git.write_text('#!/usr/bin/env python3\nimport os, sys\n'
                            'args = [os.environ["FIXTURE_SOURCE"] if arg == "https://github.com/example/foundation.git" else arg for arg in sys.argv[1:]]\n'
                            'assert "fixture-private-token" not in " ".join(args)\n'
                            f'os.execv({actual_git!r}, [{actual_git!r}, *args])\n')
        fake_git.chmod(0o755)
        self.environment = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                                FIXTURE_SOURCE=str(self.source), GH_TOKEN='fixture-private-token')

    @staticmethod
    def git(*args):
        return subprocess.check_output(['git', *args], stderr=subprocess.DEVNULL).decode().strip()

    def commit_source(self):
        self.git('-C', str(self.source), 'add', '.')
        self.git('-C', str(self.source), 'commit', '-qm', 'fixture')
        return self.git('-C', str(self.source), 'rev-parse', 'HEAD')

    def verify(self, _options, _receipt):
        return self.commit

    def perform(self, verify=None):
        with patch.dict(os.environ, self.environment, clear=True), \
                patch.object(importer, 'verify_release', verify or self.verify), \
                redirect_stdout(io.StringIO()):
            importer.import_release(self.options)

    def assert_previous(self):
        self.assertEqual((self.destination / 'owned').read_text(), 'previous tree')
        self.assertEqual(stat.S_IMODE((self.destination / 'owned').stat().st_mode), 0o751)
        self.assertEqual(stat.S_IMODE(self.destination.stat().st_mode), 0o750)
        self.assertEqual((self.project / '.wp-plugin-base.env').read_text(), 'FOUNDATION_VERSION=v0.0.1\n')

    def test_complete_tree_including_export_ignored_templates_and_modes(self):
        self.perform()
        self.assertEqual(len(list((self.destination / 'templates/child').iterdir())), 14)
        self.assertEqual(stat.S_IMODE((self.destination / 'script.sh').stat().st_mode), 0o755)
        self.assertFalse((self.destination / '.git').exists())
        self.assertFalse((self.destination / 'owned').exists())
        self.assertEqual((self.project / '.wp-plugin-base.env').read_text(), 'FOUNDATION_VERSION=v0.0.1\n')
        self.assertEqual(sorted(path.name for path in self.project.iterdir()), ['.wp-plugin-base', '.wp-plugin-base.env'])

    def test_reject_moving_tag_before_replacement(self):
        (self.source / 'later').write_text('changed')
        self.commit_source()
        self.git('-C', str(self.source), 'tag', '-f', 'v1.9.0')
        with self.assertRaisesRegex(ValueError, 'tag moved'):
            self.perform()
        self.assert_previous()

    def test_changed_release_after_fetch_preserves_previous(self):
        calls = iter((self.commit, 'f' * 40))
        with self.assertRaisesRegex(ValueError, 'changed during import'):
            self.perform(lambda *_: next(calls))
        self.assert_previous()

    def test_failed_verification_never_fetches(self):
        with patch.object(importer, 'fetch_tree') as fetch:
            with self.assertRaisesRegex(ValueError, 'invalid signature'):
                self.perform(lambda *_: (_ for _ in ()).throw(ValueError('invalid signature')))
            fetch.assert_not_called()
        self.assert_previous()

    def test_failed_staging_preserves_previous(self):
        with patch.object(importer, 'materialize_tree', side_effect=OSError('copy failure')):
            with self.assertRaisesRegex(OSError, 'copy failure'):
                self.perform()
        self.assert_previous()

    def test_publication_failure_rolls_back_modes_and_bytes(self):
        original = Path.rename
        def rename(path, target):
            if path.name == 'tree':
                raise OSError('publication failure')
            return original(path, target)
        with patch.object(Path, 'rename', rename):
            with self.assertRaisesRegex(OSError, 'publication failure'):
                self.perform()
        self.assert_previous()

    def test_symlink_destination_preserves_external_tree(self):
        external = self.root / 'external'
        self.destination.rename(external)
        self.destination.symlink_to(external, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'never a link'):
            self.perform()
        self.assertEqual((external / 'owned').read_text(), 'previous tree')

    def test_symlink_blob_rejected(self):
        (self.source / 'escape').symlink_to('../outside')
        self.commit = self.commit_source()
        self.options.expected_commit = self.commit
        self.git('-C', str(self.source), 'tag', '-f', 'v1.9.0')
        with self.assertRaisesRegex(ValueError, 'regular files only'):
            self.perform()
        self.assert_previous()

    def test_cooperating_import_lock_rejects_overlap(self):
        (self.project / '.wp-plugin-base-import.lock').mkdir()
        with self.assertRaisesRegex(ValueError, 'holds'):
            self.perform()
        self.assert_previous()

    def test_environment_does_not_inherit_git_config_or_repository(self):
        with patch.dict(os.environ, GIT_DIR='/outside', GIT_CONFIG_COUNT='1',
                        GIT_CONFIG_VALUE_0='credential', GIT_TRACE='1'):
            environment = importer.git_environment()
        self.assertNotIn('GIT_DIR', environment)
        self.assertNotIn('GIT_CONFIG_VALUE_0', environment)
        self.assertNotIn('GIT_TRACE', environment)
        self.assertEqual(environment['GIT_CONFIG_GLOBAL'], os.devnull)

    def test_receipt_rejects_malformed_metadata_and_pin_mismatch(self):
        receipt = self.root / 'receipt'
        valid = {'version': self.options.version, 'source_provider': self.options.source_provider,
                  'source_reference': self.options.source_reference, 'source_api_base': self.options.source_api_base,
                  'commit_sha': self.commit}
        cases = [dict(valid, commit_sha='main'), dict(valid, commit_sha='f' * 40),
                  dict(valid, source_reference='other/source'), dict(valid, version='v2.0.0')]
        for fields in cases:
            with self.subTest(fields=fields):
                def write_receipt(*_, **__):
                    receipt.write_text(''.join(f'{key}={value}\n' for key, value in fields.items()))
                with patch.object(importer, 'run', write_receipt), self.assertRaises(ValueError):
                    importer.verify_release(self.options, receipt)

    def test_real_verifier_rejects_draft_before_fetch(self):
        release = self.root / 'release.json'
        release.write_text(json.dumps({'draft': True, 'prerelease': False}))
        with patch.dict(os.environ, dict(self.environment, WP_PLUGIN_BASE_FOUNDATION_RELEASE_JSON=str(release)), clear=True), \
                patch.object(importer, 'fetch_tree') as fetch:
            with self.assertRaises(ValueError):
                importer.import_release(self.options)
            fetch.assert_not_called()
        self.assert_previous()

    def test_verified_tree_matches_current_foundation_tracked_tree(self):
        commit = self.git('-C', str(ROOT), 'rev-parse', 'HEAD')
        output = self.root / 'full-foundation'
        count = importer.materialize_tree(ROOT, commit, output, importer.git_environment())
        paths = self.git('-C', str(ROOT), 'ls-tree', '-r', '--name-only', commit).splitlines()
        self.assertEqual(count, len(paths))
        for path in paths:
            self.assertTrue((output / path).is_file(), path)


if __name__ == '__main__':
    unittest.main()
