#!/usr/bin/env node
// Explicit, integrity-bound npm backports; audit verification never mutates installs.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, lstatSync, readFileSync, readdirSync, realpathSync } from 'node:fs';
import nativePath, { basename, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { classifyAudit } from './npm-audit-report.mjs';

const catalogRoot = fileURLToPath(new URL('./catalog/', import.meta.url));
const catalogPaths = Object.freeze({ 'braces-3.0.3': 'braces-3.0.3.json' });
const hash = path => createHash('sha256').update(readFileSync(path)).digest('hex');
const json = path => JSON.parse(readFileSync(path, 'utf8'));
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
export function within(root, path, implementation = nativePath) {
  const part = implementation.relative(root, path);
  return part !== '..' && !part.startsWith(`..${implementation.sep}`) && !implementation.isAbsolute(part);
}
export function npmRelative(root, path, implementation = nativePath) {
  assert(within(root, path, implementation), 'Relative npm path escapes root');
  return implementation.relative(root, path).split(implementation.sep).join('/');
}
export function isMainModule(moduleURL, entry = process.argv[1]) {
  return Boolean(entry) && existsSync(entry)
    && nativePath.relative(realpathSync(resolve(entry)), realpathSync(fileURLToPath(moduleURL))) === '';
}
function exactKeys(value, keys, label) {
  assert(record(value), `Invalid ${label}`);
  assert.deepEqual(Object.keys(value).sort(), [...keys].sort(), `Unknown or missing ${label} fields`);
}
function checkedFile(root, path) {
  assert(typeof path === 'string' && path.length > 0 && !isAbsolute(path), 'Invalid relative file path');
  const full = resolve(root, path);
  assert(within(root, full), 'File path escapes root');
  let parent = root;
  for (const part of relative(root, full).split(sep)) {
    parent = join(parent, part);
    assert(!lstatSync(parent).isSymbolicLink(), 'Symlinked provenance path');
  }
  assert(lstatSync(full).isFile() && within(root, realpathSync(full)), 'Invalid provenance file');
  return full;
}
function checkedHash(root, path, expected) {
  assert(typeof expected === 'string' && /^[a-f0-9]{64}$/.test(expected), 'Invalid SHA256 digest');
  assert.equal(hash(checkedFile(root, path)), expected, `Reviewed hash changed: ${path}`);
}
export function run(command, args, cwd, environment = process.env) {
  const env = Object.fromEntries(Object.entries(environment).filter(([key]) => !/^GIT_/i.test(key)));
  const result = spawnSync(command, args, { cwd, env, encoding: 'utf8', timeout: 120000, maxBuffer: 32 * 1024 * 1024 });
  assert(!result.error && !result.signal, `${command} did not complete`);
  return result;
}
function fileHashes(root) {
  const result = {};
  function visit(dir) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (dir === root && entry.name === 'node_modules') {
        assert(entry.isDirectory() && !entry.isSymbolicLink(), 'Invalid nested dependency directory');
        continue; // Inventoried separately as physical npm packages.
      }
      assert(!entry.isSymbolicLink(), 'Unexpected symlink inside remediated package');
      if (entry.isDirectory()) visit(path);
      else {
        assert(entry.isFile(), 'Unexpected package file type');
        result[npmRelative(root, path)] = hash(path);
      }
    }
  }
  visit(root);
  return result;
}
function installedPackages(root) {
  const packages = [];
  const seen = new Set();
  function directory(path) {
    assert(lstatSync(path).isDirectory() && !lstatSync(path).isSymbolicLink(), 'Linked package directories are unsupported');
    const physical = realpathSync(path);
    assert(within(root, physical) && !seen.has(physical), 'Escaped or duplicate physical package directory');
    seen.add(physical);
  }
  function inspect(path) {
    directory(path);
    const pkg = json(checkedFile(path, 'package.json'));
    assert(typeof pkg.name === 'string' && typeof pkg.version === 'string', 'Invalid installed package identity');
    packages.push({ path, name: pkg.name, version: pkg.version });
    modules(join(path, 'node_modules'));
  }
  function cacheData(path) {
    directory(path);
    for (const name of readdirSync(path)) {
      assert.equal(name, 'babel-loader', 'Unsupported npm build cache layout');
      const cache = join(path, name);
      directory(cache);
      for (const entry of readdirSync(cache, { withFileTypes: true })) {
        assert(entry.isFile() && !entry.isSymbolicLink() && /^[a-f0-9]{64}\.json\.gz$/.test(entry.name), 'Unsupported Babel cache entry');
      }
    }
  }
  function modules(dir) {
    if (!existsSync(dir)) return;
    directory(dir);
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.name === '.package-lock.json') {
        assert(entry.isFile() && !entry.isSymbolicLink(), 'Invalid npm installation metadata');
        continue;
      }
      if (entry.name === '.bin') {
        const bin = join(dir, entry.name);
        directory(bin);
        for (const command of readdirSync(bin, { withFileTypes: true })) {
          const path = join(bin, command.name);
          assert(command.isFile() || command.isSymbolicLink(), 'Package directory hidden in npm bin entries');
          assert(within(root, realpathSync(path)) && lstatSync(realpathSync(path)).isFile(), 'Escaped npm binary entry');
        }
        continue;
      }
      if (entry.name === '.cache') { cacheData(join(dir, entry.name)); continue; }
      assert(!entry.name.startsWith('.'), 'Unsupported hidden npm installation layout');
      const path = join(dir, entry.name);
      if (entry.name.startsWith('@')) {
        directory(path);
        for (const name of readdirSync(path)) inspect(join(path, name));
      } else inspect(path);
    }
  }
  modules(join(root, 'node_modules'));
  return packages;
}
export function inspectRemediations(projectRoot) {
  const root = resolve(projectRoot);
  assert(lstatSync(root).isDirectory() && nativePath.relative(realpathSync(root), root) === '', 'Project root must be a physical directory');
  const manifest = json(checkedFile(root, 'npm-remediations.json'));
  exactKeys(manifest, ['schemaVersion', 'packageSha256', 'lockfileSha256', 'remediations'], 'remediation manifest');
  assert.equal(manifest.schemaVersion, 1, 'Unsupported remediation schema');
  assert(Array.isArray(manifest.remediations) && manifest.remediations.length > 0, 'No explicit remediations');
  assert.equal(new Set(manifest.remediations).size, manifest.remediations.length, 'Duplicate remediation IDs');
  checkedHash(root, 'package.json', manifest.packageSha256);
  checkedHash(root, 'package-lock.json', manifest.lockfileSha256);
  const pkg = json(join(root, 'package.json'));
  const lock = json(join(root, 'package-lock.json'));
  assert(!pkg.workspaces && lock.lockfileVersion === 3 && record(lock.packages), 'Unsupported workspace or npm lock format');
  const installed = installedPackages(root);
  const packages = new Set();
  const remediations = manifest.remediations.map(id => {
    assert(typeof id === 'string' && Object.hasOwn(catalogPaths, id), 'Unknown remediation ID');
    const entry = json(checkedFile(catalogRoot, catalogPaths[id]));
    assert.equal(entry.schemaVersion, 1);
    assert.equal(entry.id, id);
    assert(!packages.has(entry.package), 'Overlapping package remediations');
    packages.add(entry.package);
    checkedHash(catalogRoot, entry.patchPath, entry.patchSha256);
    checkedHash(catalogRoot, entry.regressionScript, entry.regressionSha256);
    const instances = installed.filter(item => item.name === entry.package || basename(item.path) === entry.package);
    assert(instances.length > 0, `No installed instances of ${entry.package}`);
    for (const item of instances) {
      assert(item.name === entry.package && item.version === entry.upstreamVersion, 'Unreviewed package identity or version');
      const pin = lock.packages[npmRelative(root, item.path)];
      assert(pin && !pin.link && pin.version === entry.upstreamVersion && pin.integrity === entry.upstreamIntegrity && pin.resolved === entry.upstreamTarball, 'Unreviewed package lock entry');
    }
    return { entry, instances: instances.map(item => item.path) };
  });
  return { root, remediations };
}
export function verifyRemediations(projectRoot) {
  const state = inspectRemediations(projectRoot);
  const verified = [];
  for (const { entry, instances } of state.remediations) {
    for (const path of instances) {
      assert.deepEqual(fileHashes(path), entry.installedFiles, `Installed bytes differ: ${path}`);
      const result = run(process.execPath, [join(catalogRoot, entry.regressionScript), path], state.root);
      assert.equal(result.status, 0, `Security regression failed: ${result.stderr}`);
    }
    verified.push({ id: entry.id, package: entry.package, advisory: entry.advisory,
      range: entry.advisoryRange, severity: entry.advisorySeverity, nodes: instances.map(path => npmRelative(state.root, path)) });
  }
  return verified;
}
export function applyRemediations(projectRoot) {
  const state = inspectRemediations(projectRoot);
  const pending = [];
  // Validate all manifests, source inventories and patch applicability before any write.
  for (const { entry, instances } of state.remediations) {
    for (const path of instances) {
      const actual = fileHashes(path);
      if (isDeepStrictEqual(actual, entry.installedFiles)) continue;
      assert.deepEqual(actual, entry.pristineFiles, `Pristine bytes differ: ${path}`);
      // Git otherwise discovers a parent repository and silently skips nested-project paths.
      const args = [`--work-tree=${state.root}`, 'apply', `--directory=${npmRelative(state.root, path)}`, join(catalogRoot, entry.patchPath)];
      const check = run('git', [...args, '--check'], state.root);
      assert.equal(check.status, 0, `Cannot apply reviewed patch: ${check.stderr}`);
      pending.push(args);
    }
  }
  for (const args of pending) {
    const result = run('git', args, state.root);
    assert.equal(result.status, 0, `Patch failed: ${result.stderr}`);
  }
  return verifyRemediations(state.root);
}
export function auditRemediations(projectRoot, level = 'high') {
  const root = resolve(projectRoot);
  const verified = verifyRemediations(root);
  // Explicit CLI options override inherited omit/production/workspace/registry defaults.
  const args = ['audit', '--json', '--audit-level=info', '--include=dev', '--include=optional', '--include=peer',
    '--workspaces=false', '--global=false', '--audit=true', `--prefix=${root}`, '--registry=https://registry.npmjs.org'];
  const result = run('npm', args, root);
  process.stdout.write(result.stdout);
  process.stderr.write(result.stderr);
  const decision = classifyAudit(result.stdout, result.status, verified, level);
  console.log(JSON.stringify({ verified, ...decision }, null, 2));
  assert.equal(decision.blocked.length, 0, `Unremediated dependencies meet ${level} audit threshold`);
  return decision;
}
if (isMainModule(import.meta.url)) {
  try {
    const [operation, flag, projectRoot, levelFlag, level] = process.argv.slice(2);
    assert(['apply', 'verify', 'audit'].includes(operation) && flag === '--project-root' && projectRoot, 'Usage: npm-remediation.mjs apply|verify|audit --project-root PATH [--audit-level LEVEL]');
    assert(process.argv.length === 5 || (operation === 'audit' && process.argv.length === 7 && levelFlag === '--audit-level'), 'Unexpected CLI arguments');
    const result = operation === 'apply' ? applyRemediations(projectRoot)
      : operation === 'verify' ? verifyRemediations(projectRoot) : auditRemediations(projectRoot, level);
    if (operation !== 'audit') console.log(JSON.stringify({ operation, verified: result }, null, 2));
  } catch (error) {
    console.error(`npm remediation failed: ${error.message}`);
    process.exitCode = 1;
  }
}
