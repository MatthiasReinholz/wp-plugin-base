// The WordPress environment engine check covers what the Docker runtime loads.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { after, test } = require('node:test');
const { dockerRuntimeManifests, unsatisfiedEngines } = require('../lib/check_wordpress_env_engines.cjs');

const checker = path.resolve(__dirname, '../lib/check_wordpress_env_engines.cjs');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'foundation-wp-env-engines-'));
after(() => fs.rmSync(temporary, { recursive: true, force: true }));

// Fixture ranges are `>=<major>`. The installed tool evaluates ranges with the
// real, locked semver; this stub only has to model that contract.
const SEMVER_STUB = "exports.satisfies = (version, range) => Number(version.split('.')[0]) >= Number(range.replace('>=', ''));\n";
const supported = { node: '22.12.0', npm: '10.9.0' };

let fixtureCount = 0;
function installation(packages, toolEngines) {
  const root = path.join(temporary, `tree-${fixtureCount++}`);
  fs.mkdirSync(root);
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({ name: 'tool', engines: toolEngines }));
  for (const [location, manifest] of Object.entries({ ...packages, 'node_modules/semver': { name: 'semver' } })) {
    fs.mkdirSync(path.join(root, location), { recursive: true });
    fs.writeFileSync(path.join(root, location, 'package.json'), JSON.stringify({ version: '1.0.0', ...manifest }));
  }
  fs.writeFileSync(path.join(root, 'node_modules/semver/index.js'), SEMVER_STUB);
  return root;
}
const semver = require(path.join(installation({}), 'node_modules/semver'));
const check = (root, versions = supported) => unsatisfiedEngines(root, versions, semver);
const environment = (dependencies = {}, extra = {}) => ({ 'node_modules/@wordpress/env': { name: '@wordpress/env', dependencies, ...extra } });
const playground = {
  'node_modules/@wp-playground/cli': { name: '@wp-playground/cli', dependencies: { '@php-wasm/node': '1' }, engines: { node: '>=99' } },
  'node_modules/@php-wasm/node': { name: '@php-wasm/node', engines: { node: '>=99' } },
};

test('the unused Playground runtime may require a newer Node.js', () => {
  const root = installation({ ...environment({ '@wp-playground/cli': '1' }), ...playground });
  assert.deepEqual(check(root), []);
  assert.deepEqual(dockerRuntimeManifests(root).map((manifest) => manifest.name), ['@wordpress/env']);
});

test('a Docker runtime dependency must support the running Node.js', () => {
  const root = installation({ ...environment({ docker: '1' }), 'node_modules/docker': { name: 'docker', engines: { node: '>=24' } } });
  assert.deepEqual(check(root), ['docker@1.0.0 requires Node.js >=24']);
  assert.deepEqual(check(root, { node: '24.18.0', npm: '11.16.0' }), []);
});

test('a package shared with the Playground runtime is still checked', () => {
  const root = installation({
    ...environment({ '@wp-playground/cli': '1', shared: '1' }),
    ...playground,
    'node_modules/@wp-playground/cli': { name: '@wp-playground/cli', dependencies: { shared: '1' } },
    'node_modules/shared': { name: 'shared', engines: { node: '>=99' } },
  });
  assert.deepEqual(check(root), ['shared@1.0.0 requires Node.js >=99']);
});

test('the nearest installed copy of a dependency is the one checked', () => {
  const root = installation({
    ...environment({ nested: '1' }),
    'node_modules/@wordpress/env/node_modules/nested': { name: 'nested', engines: { node: '>=22' } },
    'node_modules/nested': { name: 'nested', version: '2.0.0', engines: { node: '>=99' } },
  });
  assert.deepEqual(check(root), []);
});

test('npm aliases resolve by directory and dependency cycles terminate', () => {
  const root = installation({
    ...environment({ 'alias-cjs': 'npm:real@1', first: '1' }),
    'node_modules/alias-cjs': { name: 'real', engines: { node: '>=99' } },
    'node_modules/first': { name: 'first', dependencies: { second: '1' } },
    'node_modules/second': { name: 'second', dependencies: { first: '1' } },
  });
  assert.deepEqual(check(root), ['real@1.0.0 requires Node.js >=99']);
  assert.deepEqual(dockerRuntimeManifests(root).map((manifest) => manifest.name).sort(), ['@wordpress/env', 'first', 'real', 'second']);
});

test('missing required dependencies fail; missing optional and peer dependencies do not', () => {
  const optional = installation(environment({ maybe: '1' }, { optionalDependencies: { maybe: '1' }, peerDependencies: { host: '1' } }));
  assert.deepEqual(check(optional), []);
  const missing = installation(environment({ absent: '1' }));
  assert.throws(() => check(missing), /@wordpress\/env requires absent, which is not installed/);
});

test('the tool manifest node and npm engines are enforced', () => {
  const root = installation(environment(), { node: '>=24', npm: '>=11' });
  assert.deepEqual(check(root), ['tool requires npm >=11', 'tool requires Node.js >=24']);
});

test('a relative installation root resolves without walking past it', () => {
  const root = installation(environment({ maybe: '1' }, { optionalDependencies: { maybe: '1' } }));
  const relative = path.relative(process.cwd(), root);
  assert.deepEqual(dockerRuntimeManifests(relative).map((manifest) => manifest.name), ['@wordpress/env']);
});

test('the CLI evaluates ranges with the installed semver and reports every failure', () => {
  const root = installation({ ...environment({ docker: '1' }), 'node_modules/docker': { name: 'docker', engines: { node: '>=99' } } }, { npm: '>=99' });
  const failure = spawnSync(process.execPath, [checker, root, '10.9.0'], { encoding: 'utf8' });
  assert.equal(failure.status, 1);
  assert.match(failure.stderr, /does not satisfy:\n- tool requires npm >=99\n- docker@1\.0\.0 requires Node\.js >=99/);

  const passing = installation(environment());
  assert.equal(spawnSync(process.execPath, [checker, passing, '10.9.0']).status, 0);
  fs.rmSync(path.join(passing, 'node_modules/semver'), { recursive: true });
  assert.match(spawnSync(process.execPath, [checker, passing, '10.9.0'], { encoding: 'utf8' }).stderr, /semver is not installed/);
  assert.match(spawnSync(process.execPath, [checker, passing], { encoding: 'utf8' }).stderr, /Usage:/);
});
