#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
project="$fixture/application"
mkdir -p "$project/.wp-plugin-base"
rsync -a --exclude node_modules --exclude build --exclude dist \
  "$ROOT_DIR/tests/fixtures/existing-application/" "$project/"
rsync -a --exclude .git --exclude node_modules --exclude .wp-plugin-base-tools --exclude dist \
  --exclude tests/fixtures/existing-application/build \
  "$ROOT_DIR/" "$project/.wp-plugin-base/"

# Snapshot all application-owned source and metadata before managed sync.
python3 - "$project" "$fixture/owned.json" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
records = {path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in root.rglob('*') if path.is_file() and '.wp-plugin-base' not in path.relative_to(root).parts
            and path.relative_to(root).as_posix() not in ('.gitignore', '.editorconfig')}
pathlib.Path(sys.argv[2]).write_text(json.dumps(records))
PY

git -C "$project" init -q
export WP_PLUGIN_BASE_ROOT="$project"
unset GH_TOKEN GITHUB_TOKEN GITLAB_TOKEN CI_JOB_TOKEN GITHUB_OUTPUT
bash "$project/.wp-plugin-base/scripts/update/sync_child_repo.sh" "$project/.wp-plugin-base.env"
test ! -e "$project/build"
test ! -e "$project/.wp-plugin-base-admin-ui"
test ! -e "$project/lib/wp-plugin-base"
(
  cd "$project"
  npm ci --ignore-scripts --no-audit --no-fund
)
bash "$project/.wp-plugin-base/scripts/ci/validate_project.sh" "$project/.wp-plugin-base.env"

php -r '$asset = require $argv[1]; foreach (["react", "react-dom", "react-jsx-runtime", "wp-components", "wp-element", "wp-i18n"] as $dependency) { if (!in_array($dependency, $asset["dependencies"], true)) { fwrite(STDERR, "Missing extracted dependency: $dependency\n"); exit(1); } } if (empty($asset["version"])) { exit(1); }' "$project/build/index.asset.php"
python3 - "$project" "$fixture/owned.json" <<'PY'
import hashlib, json, pathlib, sys, zipfile
root = pathlib.Path(sys.argv[1])
for name, expected in json.loads(pathlib.Path(sys.argv[2]).read_text()).items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == expected, f'Application-owned file changed: {name}'
assert 'Requires at least: 7.1' in (root / 'existing-application.php').read_text()
assert 'padding-left:12px' in (root / 'build/index.css').read_text()
assert 'padding-right:12px' in (root / 'build/index-rtl.css').read_text()
licenses = (root / 'build/licenses.txt').read_text()
assert '@wordpress/dataviews@19.1.0' in licenses and 'GNU GENERAL PUBLIC LICENSE' in licenses
manifest = json.loads((root / 'build/manifest.json').read_text())
chunks = [item for item in manifest['artifacts'] if item['path'].endswith('.js') and item['path'] != 'build/index.js']
assert len(chunks) >= 2, 'Actual lazy application and vendor chunks must be emitted.'
with zipfile.ZipFile(root / 'dist/existing-application.zip') as archive:
    names = archive.namelist()
    assert all(not any(part in name.split('/') for part in ('node_modules', 'src', 'tools', 'tests', '.wp-plugin-base')) for name in names)
    for item in manifest['artifacts']:
        name = 'existing-application/' + item['path']
        content = archive.read(name)
        assert hashlib.sha256(content).hexdigest() == item['sha256'], name
    assert 'existing-application/build/manifest.json' in names
print('Existing application: clean-checkout build, manifest, package, licenses, extraction, RTL and ownership contracts passed.')
PY
