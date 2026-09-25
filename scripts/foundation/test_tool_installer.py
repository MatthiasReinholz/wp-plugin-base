#!/usr/bin/env python3
"""Exercise tool installation transactions without downloading executable code."""

import hashlib
import io
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

PACKAGE_COMMAND = r'''
import json, os
from pathlib import Path
import shlex, shutil, sys
args = sys.argv[1:]
command = Path(sys.argv[0]).name
if command in ('python3', 'python'):
    if args[:2] == ['-m', 'venv']:
        target = Path(args[2]) / 'bin'
        target.mkdir(parents=True)
        shutil.copyfile(__file__, target / 'python')
        (target / 'python').chmod(0o755)
    elif args[:2] == ['-m', 'pip']:
        if args[2] == 'check':
            raise SystemExit(int(os.environ.get('FIXTURE_PIP_CHECK_FAILURE', '0')))
        assert args[2] == 'install' and '--require-hashes' in args
        lock = Path(args[args.index('-r') + 1])
        mode = 'semgrep' if lock.parent.name == 'python-semgrep' else 'lint'
        if os.environ.get('FIXTURE_PIP_FAILURE') == mode:
            raise SystemExit('fixture package installation failure')
        directory = Path(sys.argv[0]).parent
        for tool in (['semgrep'] if mode == 'semgrep' else ['yamllint', 'codespell']):
            payload = directory / (tool + '.py')
            payload.write_text('import json, sys\nprint(json.dumps(' + repr({
                'tool': tool, 'version': os.environ.get('FIXTURE_VERSION', 'old')}) +
                ' | {"arguments": sys.argv[1:]}))\n')
            entry = directory / tool
            entry.write_text('#!/usr/bin/env bash\nexec ' + shlex.quote(str(directory / 'python')) +
                              ' ' + shlex.quote(str(payload)) + ' "$@"\n')
            entry.chmod(0o755)
    else:
        os.execv(REAL_PYTHON, [REAL_PYTHON, *args])
elif command == 'npm':
    assert args == ['ci', '--ignore-scripts', '--no-audit', '--no-fund']
    if os.environ.get('FIXTURE_NPM_FAILURE') == '1':
        raise SystemExit('fixture npm installation failure')
    payload = Path('node_modules/markdownlint-cli2/markdownlint-cli2-bin.mjs')
    payload.parent.mkdir(parents=True)
    payload.write_text(json.dumps({'tool': 'markdownlint-cli2',
                                  'version': os.environ.get('FIXTURE_VERSION', 'old')}))
elif command == 'node':
    print(json.dumps(json.loads(Path(args[0]).read_text()) | {'arguments': args[1:]}))
elif command == 'curl':
    output = Path(args[args.index('-fsSLo') + 1])
    if os.environ.get('FIXTURE_CORRUPT_DOWNLOAD') == '1':
        output.write_bytes(b'corrupted archive')
    else:
        shutil.copyfile(Path(os.environ['FIXTURE_ASSETS']) / args[-1].rsplit('/', 1)[1], output)
else:
    raise SystemExit('Unexpected fixture command: ' + command)
'''


class ToolInstaller(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='tool-installer-')
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.project = self.directory / 'project'
        self.script = self.project / 'scripts/ci/install_lint_tools.sh'
        self.script.parent.mkdir(parents=True)
        source = (ROOT / 'scripts/ci/install_lint_tools.sh').read_text()
        self.bin = self.directory / 'bin'
        self.bin.mkdir()
        for command in ('python3', 'npm', 'node', 'curl'):
            path = self.bin / command
            path.write_text(f'#!{sys.executable}\nREAL_PYTHON = {sys.executable!r}\n' + PACKAGE_COMMAND)
            path.chmod(0o755)
        assets = self.directory / 'assets'
        assets.mkdir()
        versions = dict(re.findall(r"^(\w+)_VERSION='([^']+)'", source, re.MULTILINE))
        for tool, archive, entry, compression in (
            ('shellcheck', f'shellcheck-v{versions["SHELLCHECK"]}.linux.x86_64.tar.xz',
              f'shellcheck-v{versions["SHELLCHECK"]}/shellcheck', 'xz'),
            ('actionlint', f'actionlint_{versions["ACTIONLINT"]}_linux_amd64.tar.gz', 'actionlint', 'gz'),
            ('editorconfig_checker', 'editorconfig-checker-linux-amd64.tar.gz', 'editorconfig-checker', 'gz'),
            ('gitleaks', f'gitleaks_{versions["GITLEAKS"]}_linux_x64.tar.gz', 'gitleaks', 'gz'),
        ):
            payload = b'#!/usr/bin/env bash\nprintf "verified binary\\n"\n'
            with tarfile.open(assets / archive, f'w:{compression}') as bundle:
                info = tarfile.TarInfo(entry)
                info.mode = 0o755
                info.size = len(payload)
                bundle.addfile(info, io.BytesIO(payload))
            digest = hashlib.sha256((assets / archive).read_bytes()).hexdigest()
            # Only the isolated test copy trusts these local fixture archives.
            source = re.sub(rf"{tool}_sha256='[a-f0-9]+'", f"{tool}_sha256='{digest}'", source)
        self.script.write_text(source)
        for directory in ('python-lint-tools', 'python-semgrep', 'markdownlint'):
            shutil.copytree(ROOT / 'tools' / directory, self.project / 'tools' / directory,
                            ignore=shutil.ignore_patterns('node_modules'))
        # Exercise spaces, quoting, literal dollar signs, and a relative argument.
        self.destination = self.directory / 'installed tools $literal "quote"'
        self.environment = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                                WP_PLUGIN_BASE_INSTALL_TOOLS_OS='Linux',
                                WP_PLUGIN_BASE_INSTALL_TOOLS_ARCH='x86_64',
                                FIXTURE_ASSETS=str(assets))

    def install(self, selection=None, **environment):
        arguments = ['bash', str(self.script), self.destination.name]
        if selection is not None:
            arguments.append(selection)
        return subprocess.run(arguments, cwd=self.directory,
                              env=dict(self.environment, **environment), text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)

    def assert_installed(self, selection=None, **environment):
        result = self.install(selection, **environment)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def run_tool(self, tool, *arguments):
        result = subprocess.run([str(self.destination / tool), *arguments], cwd='/',
                                env=self.environment, text=True, check=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return json.loads(result.stdout)

    def snapshot(self):
        return {str(path.relative_to(self.destination)): path.read_bytes()
                for path in self.destination.rglob('*') if path.is_file()}

    def test_invalid_selection_never_creates_or_changes_destination(self):
        for selection in ('', 'semgrepp', ',yamllint', 'yamllint,', 'yamllint,,codespell',
                          'all,semgrep', 'yamllint\nsemgrep', 'yamllint, semgrep'):
            with self.subTest(selection=selection):
                self.assertNotEqual(self.install(selection).returncode, 0)
                self.assertFalse(self.destination.exists())
        self.assert_installed('yamllint')
        before = self.snapshot()
        self.assertNotEqual(self.install('yamllint,unknown').returncode, 0)
        self.assertEqual(self.snapshot(), before)

    def test_selected_directory_and_symlink_directory_are_rejected(self):
        self.destination.mkdir()
        external = self.directory / 'external'
        external.mkdir()
        (external / 'sentinel').write_text('untouched')
        for symlink in (False, True):
            path = self.destination / 'semgrep'
            if symlink:
                path.symlink_to(external, target_is_directory=True)
            else:
                path.mkdir()
            self.assertNotEqual(self.install('semgrep').returncode, 0)
            self.assertEqual(list(external.iterdir()), [external / 'sentinel'])
            self.assertEqual(list(self.destination.iterdir()), [path])
            path.unlink() if symlink else path.rmdir()

    def test_adding_python_modes_preserves_tools_and_argument_boundaries(self):
        self.assert_installed('yamllint,codespell')
        old_environments = list(self.destination.glob('.python-tools-venv.*'))
        self.assert_installed('semgrep', FIXTURE_VERSION='new')
        for tool in ('yamllint', 'codespell', 'semgrep'):
            result = self.run_tool(tool, 'argument with spaces', '$literal')
            self.assertEqual(result['version'], 'new')
            self.assertEqual(result['arguments'], ['argument with spaces', '$literal'])
        self.assertTrue(all(path.is_dir() for path in old_environments))
        self.assert_installed('yamllint')
        self.assertEqual(self.run_tool('semgrep')['tool'], 'semgrep')

    def test_default_all_keeps_semgrep_opt_in_and_preserves_existing_mode(self):
        self.assert_installed()
        self.assertFalse((self.destination / 'semgrep').exists())
        self.assert_installed('semgrep')
        self.assert_installed()
        self.assertEqual(self.run_tool('semgrep')['tool'], 'semgrep')

    def test_node_python_and_binary_updates_preserve_unrelated_environments(self):
        self.assert_installed('yamllint,markdownlint-cli2')
        before = self.snapshot()
        self.assert_installed('shellcheck')
        after = self.snapshot()
        self.assertTrue(all(after[key] == value for key, value in before.items()))
        python_wrapper = (self.destination / 'yamllint').read_bytes()
        self.assert_installed('markdownlint-cli2', FIXTURE_VERSION='new')
        self.assertEqual((self.destination / 'yamllint').read_bytes(), python_wrapper)
        self.assertEqual(self.run_tool('yamllint')['version'], 'old')
        node_wrapper = (self.destination / 'markdownlint-cli2').read_bytes()
        self.assert_installed('codespell')
        self.assertEqual((self.destination / 'markdownlint-cli2').read_bytes(), node_wrapper)
        self.assertEqual(self.run_tool('markdownlint-cli2')['version'], 'new')

    def test_failed_python_install_or_dependency_check_preserves_prior_tools(self):
        self.assert_installed('yamllint,markdownlint-cli2')
        before = self.snapshot()
        for environment in ({'FIXTURE_PIP_FAILURE': 'semgrep'}, {'FIXTURE_PIP_CHECK_FAILURE': '1'}):
            with self.subTest(environment=environment):
                self.assertNotEqual(self.install('semgrep', **environment).returncode, 0)
                self.assertEqual(self.snapshot(), before)
                self.assertEqual(self.run_tool('yamllint')['version'], 'old')
                self.assertEqual(self.run_tool('markdownlint-cli2')['version'], 'old')
                self.assertEqual(len(list(self.destination.glob('.python-tools-venv.*'))), 1)
                self.assertFalse(list(self.destination.glob('.tool-install.*')))

    def test_failed_node_install_does_not_activate_prepared_python_environment(self):
        self.assert_installed('yamllint,markdownlint-cli2')
        before = self.snapshot()
        result = self.install('codespell,markdownlint-cli2', FIXTURE_NPM_FAILURE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(len(list(self.destination.glob('.python-tools-venv.*'))), 1)
        self.assertEqual(len(list(self.destination.glob('.node-tools.*'))), 1)

    def test_checksum_failure_preserves_all_existing_tools(self):
        self.assert_installed('shellcheck,yamllint,markdownlint-cli2')
        before = self.snapshot()
        self.assertNotEqual(self.install('shellcheck', FIXTURE_CORRUPT_DOWNLOAD='1').returncode, 0)
        self.assertEqual(self.snapshot(), before)

    def test_legacy_environment_remains_usable_during_upgrade(self):
        legacy = self.destination / '.python-tools-venv'
        subprocess.run([str(self.bin / 'python3'), '-m', 'venv', str(legacy)],
                        env=self.environment, check=True)
        subprocess.run([str(legacy / 'bin/python'), '-m', 'pip', 'install', '--require-hashes',
                        '-r', str(self.project / 'tools/python-lint-tools/requirements.txt')],
                        env=self.environment, check=True)
        wrapper = self.destination / 'yamllint'
        wrapper.write_text('#!/usr/bin/env bash\nexec ' + shlex.quote(str(legacy / 'bin/yamllint')) + ' "$@"\n')
        wrapper.chmod(0o755)
        self.assert_installed('semgrep', FIXTURE_VERSION='new')
        self.assertEqual(self.run_tool('yamllint')['version'], 'new')
        self.assertTrue(legacy.is_dir())
        old_tool = subprocess.check_output([str(legacy / 'bin/yamllint')], env=self.environment, text=True)
        self.assertEqual(json.loads(old_tool)['version'], 'old')


if __name__ == '__main__':
    unittest.main()
