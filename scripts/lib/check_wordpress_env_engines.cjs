// Enforce the engines of the WordPress environment tooling that actually runs.
//
// npm's engine-strict applies to every installed package. @wordpress/env also
// installs its Playground runtime (@wp-playground/cli and the @php-wasm/* graph),
// which declares a newer Node.js floor but is loaded only for
// `wp-env --runtime=playground`. The foundation always uses the default Docker
// runtime, so this check enforces the tool manifest's node and npm engines and
// engines.node of every package reachable from @wordpress/env without entering
// the Playground runtime.
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const ENTRY_PACKAGE = '@wordpress/env';
const UNUSED_RUNTIME_PACKAGES = new Set(['@wp-playground/cli']);
const USAGE = 'Usage: check_wordpress_env_engines.cjs <installation-directory> <npm-version>';

function readManifest(directory) {
  return JSON.parse(fs.readFileSync(path.join(directory, 'package.json'), 'utf8'));
}

// Node.js resolution: the nearest node_modules directory from the requiring
// package up to the installation root. Dependency keys name the directory, so
// npm aliases resolve as Node.js loads them.
function resolvePackage(root, fromDirectory, name) {
  for (let directory = fromDirectory; ; directory = path.dirname(directory)) {
    const candidate = path.join(directory, 'node_modules', name);
    if (fs.existsSync(path.join(candidate, 'package.json'))) return candidate;
    if (directory === root || path.dirname(directory) === directory) return null;
  }
}

// Manifests of every installed package the Docker runtime can load.
function dockerRuntimeManifests(root) {
  root = path.resolve(root);
  const entry = resolvePackage(root, root, ENTRY_PACKAGE);
  if (!entry) throw new Error(`${ENTRY_PACKAGE} is not installed in ${root}`);
  const manifests = new Map();
  const pending = [entry];
  while (pending.length) {
    const directory = pending.pop();
    if (manifests.has(directory)) continue;
    const manifest = readManifest(directory);
    manifests.set(directory, manifest);
    // Optional and peer dependencies are checked when installed and may be
    // absent; an optional entry overrides a dependency of the same name.
    const mayBeAbsent = new Set([...Object.keys(manifest.optionalDependencies ?? {}), ...Object.keys(manifest.peerDependencies ?? {})]);
    for (const name of new Set([...Object.keys(manifest.dependencies ?? {}), ...mayBeAbsent])) {
      if (UNUSED_RUNTIME_PACKAGES.has(name)) continue;
      const dependency = resolvePackage(root, directory, name);
      if (dependency) pending.push(dependency);
      else if (!mayBeAbsent.has(name)) throw new Error(`${manifest.name} requires ${name}, which is not installed`);
    }
  }
  return [...manifests.values()];
}

// One message per unsatisfied engine range: the tool manifest's node and npm
// ranges, and engines.node of every package the Docker runtime can load.
function unsatisfiedEngines(root, versions, semver) {
  const label = (manifest) => (manifest.version ? `${manifest.name}@${manifest.version}` : manifest.name);
  const violates = (version, range) => range && !semver.satisfies(version, range, { includePrerelease: true });
  const tool = readManifest(path.resolve(root));
  const failures = [];
  if (violates(versions.npm, tool.engines?.npm)) failures.push(`${label(tool)} requires npm ${tool.engines.npm}`);
  for (const manifest of [tool, ...dockerRuntimeManifests(root)]) {
    if (violates(versions.node, manifest.engines?.node)) failures.push(`${label(manifest)} requires Node.js ${manifest.engines.node}`);
  }
  return failures;
}

function main([root, npmVersion]) {
  if (!root || !npmVersion) throw new Error(USAGE);
  root = path.resolve(root);
  // semver is a direct, exact-pinned tool dependency, so ranges are evaluated
  // with the reviewed copy rather than whatever the caller has installed.
  const semverDirectory = resolvePackage(root, root, 'semver');
  if (!semverDirectory) throw new Error('semver is not installed with the WordPress environment tooling');
  const versions = { node: process.versions.node, npm: npmVersion };
  const failures = unsatisfiedEngines(root, versions, require(semverDirectory));
  if (failures.length) {
    throw new Error(`Node.js ${versions.node} with npm ${versions.npm} does not satisfy:\n${failures.map((failure) => `- ${failure}`).join('\n')}`);
  }
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    console.error(`WordPress environment engine check failed: ${error.message}`);
    process.exit(1);
  }
}

module.exports = { dockerRuntimeManifests, unsatisfiedEngines };
