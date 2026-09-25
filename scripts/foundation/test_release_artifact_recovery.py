#!/usr/bin/env python3
"""Exercise publication/recovery adapters with host responses and real ZIP bytes."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]

HOST_CLIENT = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
args = sys.argv[1:]
remote = pathlib.Path(os.environ['FIXTURE_REMOTE'])
assets = [{'name': p.name, 'size': p.stat().st_size} for p in remote.iterdir()]
if pathlib.Path(sys.argv[0]).name == 'gh':
    if args[:2] == ['release', 'view']:
        if os.environ.get('FIXTURE_RELEASE_EXISTS') == 'false':
            raise SystemExit(1)
        print(json.dumps({'isDraft': False, 'isPrerelease': False, 'assets': assets}))
    elif args[:2] == ['release', 'download']:
        target = pathlib.Path(args[args.index('--dir') + 1])
        name = args[args.index('--pattern') + 1]
        shutil.copyfile(remote / name, target / name)
    else:
        with pathlib.Path(os.environ['FIXTURE_MUTATION']).open('a') as log:
            log.write(json.dumps(args) + '\n')
        if os.environ.get('FIXTURE_ALLOW_MUTATION') != 'true':
            raise SystemExit('Unexpected mutation')
        if args[:2] == ['release', 'create'] and os.environ.get('FIXTURE_CREATE_FAIL') == 'true':
            raise SystemExit('Host creation failed')
else:
    assert 'private-fixture-token' not in ' '.join(args)
    header = args[args.index('--header') + 1]
    assert header.startswith('@') and pathlib.Path(header[1:]).read_text() == 'PRIVATE-TOKEN: private-fixture-token\n'
    url = next(arg for arg in args if arg.startswith('https://'))
    target = pathlib.Path(args[args.index('--output') + 1])
    if '/releases/' in url:
        target.write_text(json.dumps({'tag_name': '1.2.3', 'upcoming_release': False,
            'assets': {'links': [{'name': p.name, 'url': 'https://gitlab.com/uploads/' + p.name} for p in remote.iterdir()]}}))
        print('200')
    else:
        shutil.copyfile(remote / url.rsplit('/', 1)[1], target)
'''


class ArtifactRecovery(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.project = self.directory / 'project'
        shutil.copytree(ROOT / 'tests/fixtures/standard-plugin', self.project)
        self.remote = self.directory / 'remote'
        self.remote.mkdir()
        self.bin = self.directory / 'bin'
        self.bin.mkdir()
        for command in ('gh', 'curl'):
            path = self.bin / command
            path.write_text(HOST_CLIENT)
            path.chmod(0o755)
        cosign = self.bin / 'cosign'
        cosign.write_text('#!/usr/bin/env bash\nexit "${FIXTURE_SIGNATURE_EXIT:-0}"\n')
        cosign.chmod(0o755)
        with zipfile.ZipFile(self.remote / 'standard-plugin.zip', 'w') as archive:
            archive.writestr('standard-plugin/standard-plugin.php', '<?php // verified bytes\n')
        (self.remote / 'standard-plugin.zip.sigstore.json').write_text('{}')
        (self.remote / 'standard-plugin.zip.sbom.cdx.json').write_text('{}')
        self.environment = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                                WP_PLUGIN_BASE_ROOT=str(self.project),
                                GITHUB_REPOSITORY='example/standard-plugin',
                                CI_PROJECT_PATH='example/standard-plugin',
                                AUTOMATION_API_BASE='https://gitlab.com/api/v4',
                                GITLAB_TOKEN='private-fixture-token',
                                FIXTURE_REMOTE=str(self.remote),
                                FIXTURE_MUTATION=str(self.directory / 'mutation'))
        # Fixtures assert stdout and must not append outputs to the enclosing CI job.
        self.environment.pop('GITHUB_OUTPUT', None)

    def run_script(self, name, *arguments, **environment):
        return subprocess.run(['bash', str(ROOT / 'scripts/release' / name), *arguments],
                              cwd=self.project, env=dict(self.environment, **environment),
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)

    def test_both_hosts_restore_exact_published_bytes(self):
        for provider in ('github', 'gitlab'):
            with self.subTest(provider=provider):
                result = self.run_script(f'restore_{provider}_release_assets.sh', '1.2.3', '.wp-plugin-base.env')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((self.project / 'dist/standard-plugin.zip').read_bytes(),
                                  (self.remote / 'standard-plugin.zip').read_bytes())
                self.assertEqual((self.project / 'dist/package/standard-plugin/standard-plugin.php').read_text(),
                                  '<?php // verified bytes\n')

    def test_signature_failure_never_replaces_existing_payload(self):
        (self.project / 'dist').mkdir(exist_ok=True)
        payload = self.project / 'dist/standard-plugin.zip'
        payload.write_bytes(b'existing local payload')
        for provider in ('github', 'gitlab'):
            with self.subTest(provider=provider):
                result = self.run_script(f'restore_{provider}_release_assets.sh', '1.2.3', '.wp-plugin-base.env', FIXTURE_SIGNATURE_EXIT='1')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(payload.read_bytes(), b'existing local payload')

    def test_repair_cannot_replace_existing_github_payload(self):
        notes = self.project / 'notes.md'
        notes.write_text('Repair evidence')
        (self.remote / 'dist-foundation-release.json').write_text('{"commit":"original"}')
        for filename, version, options in [
            ('standard-plugin.zip', '1.2.3', []),
            ('standard-plugin.zip', '1.2.3-beta.1', ['--prerelease']),
            ('dist-foundation-release.json', 'v1.2.3', []),
        ]:
            with self.subTest(version=version):
                payload = self.project / filename
                payload.write_bytes(b'different package')
                result = self.run_script('publish_github_release.sh', '--repair', *options,
                                          version, version, str(notes), str(payload))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('differs from the rebuilt payload', result.stderr)
                self.assertFalse((self.directory / 'mutation').exists())

    def test_prerelease_publication_preserves_flags_and_creation_failure(self):
        notes = self.project / 'notes.md'
        notes.write_text('Prerelease')
        payload = self.project / 'standard-plugin.zip'
        shutil.copyfile(self.remote / payload.name, payload)
        log = self.directory / 'mutation'
        for exists in ('false', 'true'):
            result = self.run_script('publish_github_release.sh', '--repair', '--prerelease',
                                      '1.2.3-beta.1', '1.2.3-beta.1', str(notes), str(payload),
                                      FIXTURE_RELEASE_EXISTS=exists, FIXTURE_ALLOW_MUTATION='true')
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            final = calls[-1]
            if exists == 'false':
                self.assertEqual(final[:2], ['release', 'create'])
                self.assertIn('--prerelease', final)
                self.assertIn('--latest=false', final)
            else:
                self.assertEqual(final[:2], ['release', 'edit'])
                self.assertIn('--prerelease=true', final)
                self.assertIn('--draft=false', final)
                self.assertIn('--latest=false', final)
                self.assertNotIn('--latest', final)
            log.unlink()
        result = self.run_script('publish_github_release.sh', '--repair', '--prerelease',
                                  '1.2.3-beta.1', '1.2.3-beta.1', str(notes), str(payload),
                                  FIXTURE_RELEASE_EXISTS='false', FIXTURE_ALLOW_MUTATION='true', FIXTURE_CREATE_FAIL='true')
        self.assertNotEqual(result.returncode, 0)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][:2], ['release', 'create'])

    def test_foundation_metadata_is_deterministic_for_same_source(self):
        outputs = [self.project / name for name in ('first.json', 'repair.json')]
        for output in outputs:
            subprocess.run(['bash', str(ROOT / 'scripts/foundation/write_release_metadata.sh'),
                              'v1.2.3', 'a' * 40, str(output), 'github-release',
                              'example/foundation', 'https://api.github.com'],
                            env=self.environment, check=True, stdout=subprocess.PIPE)
        self.assertEqual(outputs[0].read_bytes(), outputs[1].read_bytes())

    def test_verified_archive_still_rejects_traversal_and_wrong_root(self):
        for path in ('../escape.php', 'other-plugin/file.php', 'standard-plugin/../../escape.php'):
            with self.subTest(path=path):
                with zipfile.ZipFile(self.remote / 'standard-plugin.zip', 'w') as archive:
                    archive.writestr(path, 'unsafe')
                result = self.run_script('restore_github_release_assets.sh', '1.2.3', '.wp-plugin-base.env')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('unsafe path', result.stderr)
                self.assertFalse((self.project / 'dist/package/standard-plugin').exists())

    def test_private_foundation_resolution_supports_gh_token_without_token_arguments(self):
        curl = self.bin / 'curl'
        curl.write_text(r'''#!/usr/bin/env python3
import os, pathlib, sys
args = sys.argv[1:]
assert 'private-fixture-token' not in ' '.join(args)
headers = [args[i + 1] for i, arg in enumerate(args[:-1]) if arg in ('-H', '--header')]
assert any(h.startswith('@') and pathlib.Path(h[1:]).read_text().strip().endswith('private-fixture-token') for h in headers)
pathlib.Path(os.environ['FIXTURE_MUTATION']).write_text('authenticated')
print('[]')
''')
        for provider, api in [('github-release', 'https://api.github.com'), ('gitlab-release', 'https://gitlab.com/api/v4')]:
            with self.subTest(provider=provider):
                environment = dict(self.environment, GH_TOKEN='private-fixture-token', GITHUB_TOKEN='')
                result = subprocess.run(['bash', str(ROOT / 'scripts/update/resolve_latest_foundation_version.sh'),
                                          'v1.2.3', 'example/foundation', '', provider, api],
                                        env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('update_needed=false', result.stdout)
                self.assertEqual((self.directory / 'mutation').read_text(), 'authenticated')
                (self.directory / 'mutation').unlink()
                # Verification must authenticate its API read through the same
                # protected header file, then fail on malformed host metadata.
                result = subprocess.run(['bash', str(ROOT / 'scripts/update/verify_foundation_release.sh'),
                                          'example/foundation', 'v1.2.3', '', provider, api],
                                        env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((self.directory / 'mutation').read_text(), 'authenticated')
                self.assertNotIn('Token leaked', result.stderr)


    def test_git_credentials_use_scoped_process_environment(self):
        git = self.bin / 'git'
        git.write_text(r'''#!/usr/bin/env python3
import base64, os, pathlib, sys
assert 'private-fixture-token' not in ' '.join(sys.argv)
assert os.environ['GIT_CONFIG_COUNT'] == '3'
assert os.environ['GIT_CONFIG_KEY_1'] == 'http.https://github.com/.extraheader'
header = os.environ['GIT_CONFIG_VALUE_1'].split()[-1]
assert base64.b64decode(header).decode() == 'x-access-token:private-fixture-token'
assert header not in ' '.join(sys.argv)
assert os.environ['GIT_CONFIG_VALUE_2'] == 'false'
pathlib.Path(os.environ['FIXTURE_MUTATION']).write_text(' '.join(sys.argv[1:]))
''')
        git.chmod(0o755)
        result = self.run_script('github_git.sh', 'fetch', '--tags', 'origin', GH_TOKEN='private-fixture-token')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.directory / 'mutation').read_text(), 'fetch --tags origin')
        self.assertFalse((self.project / '.git/config').exists())


    def test_current_helpers_work_outside_historical_source_checkout(self):
        driver = self.directory / 'trusted-main'
        shutil.copytree(ROOT / 'scripts', driver / 'scripts')
        shutil.copytree(ROOT / 'docs', driver / 'docs')
        result = subprocess.run(['bash', str(driver / 'scripts/release/restore_github_release_assets.sh'),
                                  '1.2.3', '.wp-plugin-base.env'], cwd=self.project, env=self.environment,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.project / '.wp-plugin-base/scripts/release/restore_github_release_assets.sh').exists())
        result = subprocess.run(['bash', str(driver / 'scripts/ci/validate_config.sh'), '--scope', 'deploy-structure',
                                  '.wp-plugin-base.env'], cwd=self.project, env=self.environment,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_reusable_repair_commands_honor_custom_config_path(self):
        (self.project / '.wp-plugin-base').symlink_to(ROOT, target_is_directory=True)
        subprocess.run(['bash', str(ROOT / 'scripts/update/sync_child_repo.sh')],
                        cwd=self.project, env=self.environment, check=True, stdout=subprocess.PIPE)
        (self.project / '.wp-plugin-base.env').rename(self.project / 'release.env')
        driver = self.directory / 'wp-plugin-base-release-driver'
        shutil.copytree(ROOT / 'scripts', driver / 'scripts')
        shutil.copytree(ROOT / 'docs', driver / 'docs')
        workflow = ROOT / '.github/workflows/release.yml'
        steps = json.loads(subprocess.check_output([
            'ruby', '-ryaml', '-rjson', '-e',
            'puts JSON.generate(YAML.load_file(ARGV[0]).fetch("jobs").fetch("release").fetch("steps"))',
            str(workflow)], text=True))
        names = {'Validate tag and metadata versions', 'Lint PHP', 'Lint JavaScript',
                  'Build package', 'Generate GitHub release body'}
        environment = dict(self.environment, RELEASE_CONFIG_PATH='release.env', RUNNER_TEMP=str(self.directory))
        for step in steps:
            if step['name'] not in names:
                continue
            command = step['run'].replace('${{ steps.version.outputs.value }}', '1.2.3')
            result = subprocess.run(['bash', '-e', '-c', command], cwd=self.project, env=environment,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
            self.assertEqual(result.returncode, 0, f'{step["name"]}: {result.stderr}')
        self.assertTrue((self.project / 'dist/standard-plugin.zip').is_file())
        self.assertTrue((self.project / 'dist/release-body.md').is_file())



if __name__ == '__main__':
    unittest.main()
