#!/usr/bin/env python3
"""Import a complete verified foundation tree without running imported code."""

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

SCRIPT_DIR = Path(__file__).resolve().parent


def git_environment():
    """Do not inherit another repository, hooks, filters, tracing or Git config."""
    environment = {key: value for key, value in os.environ.items()
                    if not key.startswith('GIT_')}
    environment.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_TERMINAL_PROMPT='0')
    return environment


def run(arguments, *, environment=None):
    # Failure messages name the operation, never dump credential-bearing output.
    result = subprocess.run(arguments, env=environment, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise ValueError(f'{Path(arguments[0]).name} operation failed ({result.returncode}).')
    return result.stdout


def verify_release(options, receipt):
    receipt.write_bytes(b'')
    run(['bash', str(SCRIPT_DIR / 'verify_foundation_release.sh'),
          options.source_reference, options.version, str(receipt), options.source_provider,
          options.source_api_base, options.source_sigstore_issuer])
    fields = {}
    for line in receipt.read_text().splitlines():
        key, separator, value = line.partition('=')
        if not separator or key in fields:
            raise ValueError('Malformed foundation verification receipt.')
        fields[key] = value
    expected = {'version': options.version, 'source_provider': options.source_provider,
                'source_reference': options.source_reference,
                'source_api_base': options.source_api_base}
    if any(fields.get(key) != value for key, value in expected.items()):
        raise ValueError('Foundation verification receipt does not match the requested source.')
    commit = fields.get('commit_sha', '')
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Foundation verification receipt has an invalid commit.')
    if options.expected_commit and commit != options.expected_commit:
        raise ValueError('Verified foundation commit does not match --expected-commit.')
    return commit


def fetch_tree(options, repository, commit, environment):
    run(['git', 'init', '--bare', '--template=', str(repository)], environment=environment)
    # Reuse the provider's scoped, process-local authentication. Neither a token
    # nor an authenticated URL is written to disk or passed as a process argument.
    provider_script = SCRIPT_DIR.parent / 'lib/provider.sh'
    shell = '. "$1"; shift; provider="$1"; api="$2"; reference="$3"; repository="$4"; commit="$5"; version="$6"; '
    shell += 'url="$(wp_plugin_base_provider_reference_git_url "$provider" "$api" "$reference")"; '
    shell += 'wp_plugin_base_provider_git "$provider" "$api" -C "$repository" fetch --depth=1 --no-tags "$url" "$commit" "refs/tags/$version:refs/tags/import-verified"'
    run(['bash', '-c', shell, 'foundation-import', str(provider_script),
          options.source_provider, options.source_api_base, options.source_reference,
          str(repository), commit, options.version], environment=environment)
    resolved = run(['git', '-C', str(repository), 'rev-parse', '--verify',
                    'refs/tags/import-verified^{commit}'], environment=environment).decode().strip()
    if resolved != commit:
        raise ValueError('Foundation tag moved or does not identify the verified commit.')
    run(['git', '-C', str(repository), 'cat-file', '-e', f'{commit}^{{commit}}'],
        environment=environment)


def materialize_tree(repository, commit, destination, environment):
    entries = run(['git', '-C', str(repository), 'ls-tree', '-rz', '--full-tree', commit],
                  environment=environment)
    manifest = []
    seen = set()
    prefixes = {}
    for entry in entries.split(b'\0'):
        if not entry:
            continue
        metadata, raw_path = entry.split(b'\t', 1)
        mode, kind, object_id = metadata.decode('ascii').split(' ')
        path = raw_path.decode('utf-8')
        parts = PurePosixPath(path).parts
        if (not parts or path.startswith('/') or '\\' in path
                or any(part in ('.', '..') or part.casefold() == '.git' for part in parts)
                or str(PurePosixPath(path)) != path
                or any(ord(character) < 32 or ord(character) == 127 for character in path)):
            raise ValueError('Foundation tree contains an unsafe path.')
        folded = path.casefold()
        if folded in seen:
            raise ValueError('Foundation tree contains case-colliding paths.')
        seen.add(folded)
        for index in range(1, len(parts) + 1):
            prefix = '/'.join(parts[:index])
            prior = prefixes.setdefault(prefix.casefold(), prefix)
            if prior != prefix:
                raise ValueError('Foundation tree contains case-colliding directories.')
        if kind != 'blob' or mode not in ('100644', '100755'):
            raise ValueError('Foundation import supports regular files only; links and submodules are rejected.')
        if not re.fullmatch(r'[0-9a-f]{40}', object_id):
            raise ValueError('Foundation tree contains an invalid object identity.')
        manifest.append((path, mode, object_id))
    if not manifest:
        raise ValueError('Foundation tree is empty.')
    destination.mkdir(mode=0o755)
    for path, mode, object_id in manifest:
        target = destination / path
        target.parent.mkdir(parents=True, exist_ok=True)
        content = run(['git', '-C', str(repository), 'cat-file', 'blob', object_id],
                      environment=environment)
        digest = hashlib.sha1(b'blob ' + str(len(content)).encode() + b'\0' + content).hexdigest()
        if digest != object_id:
            raise ValueError('Foundation blob does not match its Git identity.')
        with target.open('xb') as stream:
            stream.write(content)
        target.chmod(0o755 if mode == '100755' else 0o644)
        if target.read_bytes() != content or stat.S_IMODE(target.stat().st_mode) != int(mode[-3:], 8):
            raise ValueError('Materialized foundation file failed byte or mode verification.')
    for directory, _, _ in os.walk(destination):
        Path(directory).chmod(0o755)
    actual = {path.relative_to(destination).as_posix() for path in destination.rglob('*')
              if path.is_file()}
    if actual != {path for path, _, _ in manifest}:
        raise ValueError('Materialized foundation tree is incomplete.')
    return len(manifest)


def replace_tree(staged, destination, backup):
    """Two renames with ordinary-failure rollback, not a crash-atomic exchange."""
    previous = destination.exists()
    if previous:
        destination.rename(backup)
    try:
        staged.rename(destination)
    except BaseException:
        if previous:
            backup.rename(destination)
        raise


def import_release(options):
    project = Path(options.project_root).resolve(strict=True)
    if not project.is_dir() or project == Path(project.anchor):
        raise ValueError('--project-root must be an existing project directory, not a filesystem root.')
    destination = project / '.wp-plugin-base'
    if destination.is_symlink() or (destination.exists() and not destination.is_dir()):
        raise ValueError('Foundation destination must be a real directory, never a link or file.')
    lock = project / '.wp-plugin-base-import.lock'
    try:
        lock.mkdir(mode=0o700)
    except FileExistsError as error:
        raise ValueError('Another import or an interrupted import holds .wp-plugin-base-import.lock; inspect it before retrying.') from error
    attempt = None
    try:
        (lock / 'owner').write_text(f'pid={os.getpid()}\n')
        attempt = Path(tempfile.mkdtemp(prefix='.wp-plugin-base-import-', dir=project))
        environment = git_environment()
        commit = verify_release(options, attempt / 'verified-release')
        fetch_tree(options, attempt / 'repository.git', commit, environment)
        count = materialize_tree(attempt / 'repository.git', commit, attempt / 'tree', environment)
        # Recheck the published contract after fetching, before replacing anything.
        if verify_release(options, attempt / 'verified-release') != commit:
            raise ValueError('Foundation release changed during import.')
        if destination.is_symlink() or (destination.exists() and not destination.is_dir()):
            raise ValueError('Foundation destination changed during import.')
        replace_tree(attempt / 'tree', destination, attempt / 'previous')
        print(f'Imported {options.version} ({commit}): {count} verified files into {destination}.')
        print('Review the vendor diff, then separately update configuration, sync and validate.')
    finally:
        if attempt is not None:
            # If rollback itself failed, retain the backup for explicit recovery.
            if (attempt / 'previous').exists() and not destination.exists():
                print(f'Previous foundation retained for recovery at {attempt / "previous"}.', file=sys.stderr)
            else:
                shutil.rmtree(attempt)
        shutil.rmtree(lock)


def parse_arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--project-root', required=True)
    parser.add_argument('--expected-commit', default='')
    parser.add_argument('--source-provider', choices=('github-release', 'gitlab-release'), default='github-release')
    parser.add_argument('--source-reference', default='MatthiasReinholz/wp-plugin-base')
    parser.add_argument('--source-api-base', default='')
    parser.add_argument('--source-sigstore-issuer', default='')
    options = parser.parse_args()
    if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', options.version):
        parser.error('--version must be an exact stable foundation tag (vX.Y.Z).')
    if options.expected_commit and not re.fullmatch(r'[0-9a-f]{40}', options.expected_commit):
        parser.error('--expected-commit must be a complete lowercase commit SHA.')
    if not re.fullmatch(r'[A-Za-z0-9_-][A-Za-z0-9_.-]*(/[A-Za-z0-9_-][A-Za-z0-9_.-]*)+', options.source_reference):
        parser.error('--source-reference must be a repository path without URL credentials.')
    if not options.source_api_base:
        options.source_api_base = ('https://api.github.com' if options.source_provider == 'github-release'
                                    else 'https://gitlab.com/api/v4')
    parsed = urlsplit(options.source_api_base)
    if (parsed.scheme != 'https' or not parsed.hostname or parsed.username is not None
            or parsed.password is not None or parsed.query or parsed.fragment
            or options.source_api_base.endswith('/') or any(character.isspace() for character in options.source_api_base)):
        parser.error('--source-api-base must be an HTTPS API URL without credentials, query or fragment.')
    return options


def main():
    try:
        import_release(parse_arguments())
    except (OSError, ValueError, UnicodeError, subprocess.SubprocessError) as error:
        print(f'Foundation import failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
