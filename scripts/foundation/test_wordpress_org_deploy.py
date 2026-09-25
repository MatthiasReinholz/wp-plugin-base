#!/usr/bin/env python3
"""Exercise SVN deployment with real file comparisons and local-only publication."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
REAL_SVN = shutil.which('svn')
REAL_SVNADMIN = shutil.which('svnadmin')
REAL_RSYNC = shutil.which('rsync')

ADAPTER = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, subprocess, sys
args = sys.argv[1:]
base = pathlib.Path(os.environ['DEPLOY_FIXTURE'])
command = pathlib.Path(sys.argv[0]).name
with (base / 'calls.jsonl').open('a') as log:
    log.write(json.dumps([command, args, os.getcwd()]) + '\n')
if command == 'git':
    assert args[2:] == ['tag', '--list', '[0-9]*.[0-9]*.[0-9]*']
    print('1.2.3')
    raise SystemExit(0)
if command == 'python3':
    if args[0].endswith('/compare_package_trees.py') and os.environ.get('FAIL_COMPARE') == 'true':
        raise SystemExit(2)
    raise SystemExit(subprocess.call([os.environ['REAL_PYTHON'], *args]))
if command == 'rsync':
    raise SystemExit(subprocess.call([os.environ['REAL_RSYNC'], *args]))
operation = args[0]
if operation == 'status':
    counter = base / 'status-count'
    count = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(count))
    if str(count) == os.environ.get('FAIL_STATUS'):
        raise SystemExit(17)
if operation == os.environ.get('FAIL_SVN'):
    raise SystemExit(19)
if os.environ.get('REAL_SVN'):
    remote = 'https://plugins.svn.wordpress.org/standard-plugin'
    args = [arg.replace(remote, (base / 'repository').as_uri()) for arg in args]
    result = subprocess.call([os.environ['REAL_SVN'], *args])
    if result:
        raise SystemExit(result)
else:
    seed = base / 'seed'
    checkout_file = base / 'checkout-path'
    if operation == 'checkout':
        checkout = pathlib.Path(args[-1])
        shutil.copytree(seed, checkout)
        (checkout / '.svn').mkdir()
        checkout_file.write_text(str(checkout))
    else:
        checkout = pathlib.Path(checkout_file.read_text())
        if operation in ('status', 'add', 'delete', 'commit'):
            assert pathlib.Path.cwd() == checkout.resolve(), 'SVN command ran outside checkout'
        if operation == 'info':
            raise SystemExit(0 if (seed / 'tags/1.2.3').is_dir() else 1)
        if operation == 'status':
            before = {p.relative_to(seed): p.read_bytes() for p in seed.rglob('*') if p.is_file()}
            after = {p.relative_to(checkout): p.read_bytes() for p in checkout.rglob('*') if p.is_file()}
            for path in sorted(before.keys() | after.keys()):
                status = '?' if path not in before else '!' if path not in after else 'M' if before[path] != after[path] else ''
                if status:
                    print(status + '       ' + str(path))
        elif operation in ('add', 'delete'):
            assert '--' in args and args[-1].endswith('@'), 'SVN path lacks operand/peg protection'
        elif operation == 'commit':
            shutil.copytree(checkout, base / 'published', ignore=shutil.ignore_patterns('.svn'))
        elif operation not in ('update', 'ls'):
            raise SystemExit('Unexpected SVN operation: ' + operation)
if operation in ('checkout', 'update'):
    checkout = pathlib.Path(args[-1]) if operation == 'checkout' else pathlib.Path(args[-1]).parent
    timestamp = 1000000000 if os.environ.get('NORMALIZE_MTIME') == 'true' else 1000000200
    for path in checkout.rglob('*'):
        if path.is_file() and '.svn' not in path.parts:
            os.utime(path, (timestamp, timestamp))
'''


class DeploymentCases:
    native = False

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='wp-svn-deploy-')
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.project = self.base / 'project with spaces'
        shutil.copytree(ROOT / 'tests/fixtures/standard-plugin', self.project)
        self.source = self.base / 'package with spaces'
        self.source.mkdir()
        for name in ('standard-plugin.php', 'readme.txt'):
            shutil.copyfile(self.project / name, self.source / name)
        (self.source / 'new directory').mkdir()
        (self.source / 'new directory/file @ name.php').write_text('new payload')
        (self.source / 'changed.php').write_text('new bytes')
        for path in self.source.rglob('*'):
            if path.is_file():
                os.utime(path, (1000000000, 1000000000))
        self.seed = self.base / 'seed'
        shutil.copytree(self.source, self.seed / 'trunk')
        shutil.rmtree(self.seed / 'trunk/new directory')
        (self.seed / 'trunk/old file.php').write_text('removed')
        (self.seed / 'trunk/changed.php').write_text('old bytes')
        (self.seed / 'tags').mkdir()
        (self.seed / 'assets').mkdir()
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        for name in ('git', 'svn', 'rsync', 'python3'):
            path = self.bin / name
            path.write_text(ADAPTER.replace('#!/usr/bin/env python3', '#!' + sys.executable, 1))
            path.chmod(0o755)
        self.environment = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                                DEPLOY_FIXTURE=str(self.base), REAL_RSYNC=REAL_RSYNC,
                                REAL_PYTHON=sys.executable,
                                REAL_SVN=REAL_SVN if self.native else '',
                                WP_PLUGIN_BASE_ROOT=str(self.project), SVN_USERNAME='fixture-user',
                                SVN_PASSWORD='fixture-password')
        self.environment.pop('WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY', None)

    def deploy(self, **environment):
        if self.native:
            subprocess.run([REAL_SVNADMIN, 'create', str(self.base / 'repository')], check=True)
            subprocess.run([REAL_SVN, 'import', '--non-interactive', '-m', 'Initial fixture',
                            str(self.seed), (self.base / 'repository').as_uri()],
                            check=True, stdout=subprocess.PIPE)
        result = subprocess.run(['bash', str(ROOT / 'scripts/release/deploy_wordpress_org.sh'),
                                  '1.2.3', '.wp-plugin-base.env', str(self.source)],
                                cwd=self.project, env=dict(self.environment, **environment),
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.calls = [json.loads(line) for line in (self.base / 'calls.jsonl').read_text().splitlines()]
        return result

    def committed(self):
        return any(command == 'svn' and args[0] == 'commit' for command, args, _ in self.calls)

    def published_file(self, path):
        if self.native:
            return subprocess.check_output([REAL_SVN, 'cat', (self.base / 'repository').as_uri() + '/' + path + '@'])
        return (self.base / 'published' / path).read_bytes()

    def test_new_tag_stages_additions_deletions_spaces_and_checksum_changes(self):
        result = self.deploy(NORMALIZE_MTIME='true')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.committed())
        for prefix in ('trunk', 'tags/1.2.3'):
            self.assertEqual(self.published_file(prefix + '/changed.php'), b'new bytes')
            self.assertEqual(self.published_file(prefix + '/new directory/file @ name.php'), b'new payload')
        if self.native:
            listing = subprocess.check_output([REAL_SVN, 'ls', (self.base / 'repository').as_uri() + '/trunk'], text=True)
            self.assertNotIn('old file.php', listing)
        else:
            self.assertFalse((self.base / 'published/trunk/old file.php').exists())

    def test_identical_tag_ignores_timestamp_changes(self):
        shutil.copytree(self.source, self.seed / 'tags/1.2.3')
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.published_file('tags/1.2.3/changed.php'), b'new bytes')

    def test_matching_tag_and_trunk_are_idempotent(self):
        shutil.copytree(self.source, self.seed / 'tags/1.2.3')
        shutil.rmtree(self.seed / 'trunk')
        shutil.copytree(self.source, self.seed / 'trunk')
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('No WordPress.org changes', result.stdout)
        self.assertFalse(self.committed())

    def test_same_size_timestamp_different_tag_is_rejected(self):
        shutil.copytree(self.source, self.seed / 'tags/1.2.3')
        (self.seed / 'tags/1.2.3/changed.php').write_text('bad bytes')
        result = self.deploy(NORMALIZE_MTIME='true')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('differs from the release package', result.stderr)
        self.assertFalse(self.committed())

    def test_comparison_failure_is_not_treated_as_equality(self):
        shutil.copytree(self.source, self.seed / 'tags/1.2.3')
        result = self.deploy(FAIL_COMPARE='true')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unable to compare', result.stderr)
        self.assertFalse(self.committed())

    def test_initial_status_failure_never_commits(self):
        result = self.deploy(FAIL_STATUS='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('working copy status', result.stderr)
        self.assertFalse(self.committed())

    def test_final_status_failure_never_reports_success(self):
        result = self.deploy(FAIL_STATUS='2')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('working copy status', result.stderr)
        self.assertFalse(self.committed())
        self.assertNotIn('No WordPress.org changes', result.stdout)

    def test_add_failure_never_commits(self):
        result = self.deploy(FAIL_SVN='add')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.committed())

    def test_delete_failure_never_commits(self):
        result = self.deploy(FAIL_SVN='delete')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.committed())

    def test_commit_failure_never_reports_publication(self):
        result = self.deploy(FAIL_SVN='commit')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Deployed standard-plugin', result.stdout)


class PortableDeployment(DeploymentCases, unittest.TestCase):
    """Real rsync and a cwd-enforcing SVN adapter run on every supported host."""


@unittest.skipUnless(REAL_SVN and REAL_SVNADMIN, 'Local SVN integration requires svn and svnadmin')
class LocalRepositoryDeployment(DeploymentCases, unittest.TestCase):
    """The same cases publish only to a temporary file:// SVN repository."""

    native = True


class PackageComparison(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='wp-package-compare-')
        self.addCleanup(temporary.cleanup)
        self.left = Path(temporary.name) / 'left'
        self.right = Path(temporary.name) / 'right'
        self.left.mkdir()
        self.right.mkdir()

    def compare(self):
        return subprocess.run([sys.executable, str(ROOT / 'scripts/release/compare_package_trees.py'),
                                str(self.left), str(self.right)], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True)

    def test_symlink_targets_are_compared_without_following_them(self):
        (self.left / 'link').symlink_to('missing-target')
        (self.right / 'link').symlink_to('missing-target')
        self.assertEqual(self.compare().returncode, 0)
        (self.right / 'link').unlink()
        (self.right / 'link').symlink_to('other-target')
        self.assertEqual(self.compare().returncode, 1)

    def test_directory_and_file_are_not_equivalent(self):
        (self.left / 'entry').mkdir()
        (self.right / 'entry').write_text('')
        self.assertEqual(self.compare().returncode, 1)

    def test_svn_metadata_is_ignored(self):
        (self.right / '.svn').mkdir()
        (self.right / '.svn/private-metadata').write_text('checkout details')
        self.assertEqual(self.compare().returncode, 0)

    def test_unreadable_tree_is_an_error_not_a_mismatch(self):
        self.right.rmdir()
        result = self.compare()
        self.assertEqual(result.returncode, 2)
        self.assertIn('Package comparison failed', result.stderr)


if __name__ == '__main__':
    unittest.main()
