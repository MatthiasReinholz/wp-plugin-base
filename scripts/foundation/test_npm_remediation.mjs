import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { cpSync, mkdtempSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, posix, win32 } from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyRemediations, verifyRemediations, run, within, npmRelative } from '../security/npm-remediation.mjs';
import { classifyAudit } from '../security/npm-audit-report.mjs';

const fixture = fileURLToPath(new URL('../../tests/fixtures/npm-remediation/', import.meta.url));
const cli = fileURLToPath(new URL('../security/npm-remediation.mjs', import.meta.url));
const temporary = mkdtempSync(join(tmpdir(), 'foundation-npm-remediation-'));
const baseline = join(temporary, 'baseline');
const digest = path => createHash('sha256').update(readFileSync(path)).digest('hex');
const readJson = path => JSON.parse(readFileSync(path, 'utf8'));
const writeJson = (path, value) => writeFileSync(path, JSON.stringify(value, null, 2) + '\n');
function manifest(root, extra = {}) {
  writeJson(join(root, 'npm-remediations.json'), { schemaVersion: 1,
    packageSha256: digest(join(root, 'package.json')), lockfileSha256: digest(join(root, 'package-lock.json')),
    remediations: ['braces-3.0.3'], ...extra });
}
function project() {
  const root = mkdtempSync(join(temporary, 'project-'));
  cpSync(baseline, root, { recursive: true });
  manifest(root);
  return root;
}
before(() => {
  mkdirSync(baseline);
  for (const file of ['package.json', 'package-lock.json']) cpSync(join(fixture, file), join(baseline, file));
  const install = run('npm', ['ci', '--ignore-scripts', '--include=dev', '--include=optional', '--include=peer', '--no-audit', '--no-fund', '--registry=https://registry.npmjs.org'], baseline);
  assert.equal(install.status, 0, install.stderr);
});
after(() => rmSync(temporary, { recursive: true, force: true }));

test('real pristine parser is rejected; exact patch passes attack/semantics tests and is idempotent', () => {
  const root = project();
  assert.throws(() => verifyRemediations(root), /Installed bytes differ/);
  const packageHash = digest(join(root, 'package.json'));
  const lockHash = digest(join(root, 'package-lock.json'));
  const first = applyRemediations(root);
  assert.deepEqual(applyRemediations(root), first);
  assert.equal(digest(join(root, 'package.json')), packageHash);
  assert.equal(digest(join(root, 'package-lock.json')), lockHash);
  assert.equal(readJson(join(root, 'node_modules/braces/package.json')).version, '3.0.3');
});

test('subprocess isolation removes Git environment keys irrespective of casing', () => {
  const result = run(process.execPath, ['-e', 'console.log(JSON.stringify(Object.keys(process.env).filter(key => /^git_/i.test(key))))'], temporary,
    { ...process.env, Git_Dir: 'untrusted-directory', git_work_tree: 'untrusted-work-tree', GIT_INDEX_FILE: 'untrusted-index' });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), []);
});

test('real CLI patches a nested project in a linked worktree despite inherited Git context', () => {
  const repository = mkdtempSync(join(temporary, 'repository-'));
  const worktree = join(temporary, 'linked-worktree');
  for (const args of [
    ['init'],
    ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--allow-empty', '-m', 'Fixture'],
    ['worktree', 'add', '--detach', worktree],
  ]) {
    const result = run('git', ['-c', 'commit.gpgsign=false', '-c', `core.hooksPath=${join(temporary, 'no-hooks')}`, ...args], repository);
    assert.equal(result.status, 0, result.stderr);
  }
  const root = join(worktree, '.wp-plugin-base-admin-ui');
  cpSync(baseline, root, { recursive: true });
  manifest(root);
  assert.throws(() => verifyRemediations(root), /Installed bytes differ/);
  const result = spawnSync(process.execPath, [cli, 'apply', '--project-root', root], {
    cwd: root, encoding: 'utf8', timeout: 120000,
    env: { ...process.env, GIT_DIR: join(temporary, 'nonexistent-git-dir'), GIT_WORK_TREE: repository },
  });
  assert.equal(result.status, 0, result.stderr + result.stdout);
  assert.match(result.stdout, /braces-3.0.3/);
  assert.equal(verifyRemediations(root)[0].nodes[0], 'node_modules/braces');
  assert.deepEqual(applyRemediations(root), verifyRemediations(root));
});

test('all nested physical copies are patched; drift in the second copy prevents first mutation', () => {
  const root = project();
  const holder = join(root, 'node_modules/holder');
  mkdirSync(join(holder, 'node_modules'), { recursive: true });
  writeJson(join(holder, 'package.json'), { name: 'holder', version: '1.0.0' });
  cpSync(join(root, 'node_modules/braces'), join(holder, 'node_modules/braces'), { recursive: true });
  const lock = readJson(join(root, 'package-lock.json'));
  lock.packages['node_modules/holder/node_modules/braces'] = { ...lock.packages['node_modules/braces'] };
  writeJson(join(root, 'package-lock.json'), lock);
  manifest(root);
  const target = join(holder, 'node_modules/braces/index.js');
  const pristine = readFileSync(target);
  writeFileSync(target, 'unreviewed mutation');
  const untouched = digest(join(root, 'node_modules/braces/lib/parse.js'));
  assert.throws(() => applyRemediations(root), /Pristine bytes differ/);
  assert.equal(digest(join(root, 'node_modules/braces/lib/parse.js')), untouched);
  writeFileSync(target, pristine);
  assert.equal(applyRemediations(root)[0].nodes.length, 2);
});

for (const [name, change, pattern] of [
  ['unknown remediation', root => manifest(root, { remediations: ['unreviewed-advisory'] }), /Unknown remediation/],
  ['duplicate remediation', root => manifest(root, { remediations: ['braces-3.0.3', 'braces-3.0.3'] }), /Duplicate/],
  ['unknown manifest field', root => manifest(root, { ignore: ['all'] }), /Unknown or missing/],
  ['manifest drift', root => writeFileSync(join(root, 'package.json'), '{}'), /Reviewed hash changed/],
  ['lock drift', root => writeFileSync(join(root, 'package-lock.json'), '{}'), /Reviewed hash changed/],
  ['wrong version', root => { const p = join(root, 'node_modules/braces/package.json'); const v = readJson(p); v.version = '3.0.4'; writeJson(p, v); }, /Unreviewed package/],
  ['untracked package file', root => writeFileSync(join(root, 'node_modules/braces/extra.js'), ''), /Pristine bytes differ/],
  ['linked package', root => symlinkSync(join(root, 'node_modules/braces'), join(root, 'node_modules/alias')), /Linked package/],
  ['hidden bin package', root => mkdirSync(join(root, 'node_modules/.bin/braces'), { recursive: true }), /Package directory hidden/],
  ['escaped binary', root => { mkdirSync(join(root, 'node_modules/.bin')); symlinkSync('/bin/sh', join(root, 'node_modules/.bin/tool')); }, /Escaped npm binary/],
  ['linked manifest', root => { const p = join(root, 'npm-remediations.json'); cpSync(p, join(root, 'other.json')); rmSync(p); symlinkSync('other.json', p); }, /Symlinked/],
  ['linked package file', root => { const p = join(root, 'node_modules/braces/index.js'); rmSync(p); symlinkSync(join(root, 'package.json'), p); }, /symlink/],
  ['workspace project', root => { const p = join(root, 'package.json'); const v = readJson(p); v.workspaces = ['child']; writeJson(p, v); manifest(root); }, /Unsupported workspace/],
]) test(`${name} fails closed`, () => assert.throws(() => applyRemediations(changeProject(change)), pattern));
function changeProject(change) { const root = project(); change(root); return root; }

test('real audit neutralizes inherited omit, registry and workspace defaults without mutation', () => {
  const root = project();
  applyRemediations(root);
  const beforeHash = digest(join(root, 'node_modules/braces/lib/parse.js'));
  const result = run(process.execPath, [cli, 'audit', '--project-root', root, '--audit-level', 'high'], root,
    { ...process.env, NPM_CONFIG_OMIT: 'dev', NPM_CONFIG_REGISTRY: 'https://invalid.example', NPM_CONFIG_WORKSPACES: 'true', NODE_ENV: 'production' });
  assert.equal(result.status, 0, result.stderr + result.stdout);
  assert.match(result.stdout, /GHSA-vfj7-8cjw-p6xm/);
  assert.match(result.stdout, /locallyRemediated/);
  assert.equal(digest(join(root, 'node_modules/braces/lib/parse.js')), beforeHash);
});

test('standard build cache data is accepted but cannot conceal executable packages', () => {
  const root = project();
  const cache = join(root, 'node_modules/.cache/babel-loader');
  mkdirSync(cache, { recursive: true });
  writeFileSync(join(cache, 'a'.repeat(64) + '.json.gz'), 'cache data');
  applyRemediations(root);
  writeJson(join(cache, 'package.json'), { name: 'braces', version: '3.0.3' });
  assert.throws(() => verifyRemediations(root), /Unsupported Babel cache/);
  rmSync(join(cache, 'package.json'));
  writeFileSync(join(cache, 'index.js'), 'module.exports = {};');
  assert.throws(() => verifyRemediations(root), /Unsupported Babel cache/);
});

const verified = [{ id: 'braces-3.0.3', package: 'braces', advisory: 'GHSA-vfj7-8cjw-p6xm', range: '<=3.0.3', severity: 'high', nodes: ['node_modules/braces'] }];
function report() {
  return { auditReportVersion: 2, vulnerabilities: {
    braces: { name: 'braces', severity: 'high', via: [{ name: 'braces', dependency: 'braces', range: '<=3.0.3', severity: 'high', url: 'https://github.com/advisories/GHSA-vfj7-8cjw-p6xm' }], effects: ['consumer'], nodes: ['node_modules/braces'] },
    consumer: { name: 'consumer', severity: 'high', via: ['braces'], effects: [], nodes: ['node_modules/consumer'] },
  }, metadata: { vulnerabilities: { info: 0, low: 0, moderate: 0, high: 2, critical: 0, total: 2 } } };
}
test('only the fully verified advisory and complete ancestor graph qualify', () => {
  assert.deepEqual(classifyAudit(JSON.stringify(report()), 1, verified).locallyRemediated, ['braces', 'consumer']);
});
for (const [name, change] of [
  ['wrong status', r => { r.status = 0; }],
  ['wrong counts', r => { r.data.metadata.vulnerabilities.total = 0; }],
  ['unknown schema', r => { r.data.auditReportVersion = 3; }],
  ['missing reverse edge', r => { r.data.vulnerabilities.braces.effects = []; }],
  ['unknown source', r => { r.data.vulnerabilities.consumer.via = ['absent']; }],
  ['changed advisory', r => { r.data.vulnerabilities.braces.via[0].range = '*'; }],
  ['unverified node', r => { r.data.vulnerabilities.braces.nodes.push('node_modules/other/braces'); }],
  ['cycle', r => { r.data.vulnerabilities.braces.via = ['consumer']; r.data.vulnerabilities.consumer.effects = ['braces']; }],
  ['hidden severity', r => { r.data.vulnerabilities.consumer.severity = 'low'; }],
]) test(`audit rejects ${name}`, () => {
  const input = { data: report(), status: 1 }; change(input);
  assert.throws(() => classifyAudit(JSON.stringify(input.data), input.status, verified));
});
test('unrelated findings remain visible and enforce the caller threshold', () => {
  const r = report();
  r.vulnerabilities.other = { name: 'other', severity: 'moderate', via: [{ name: 'other', severity: 'moderate', url: 'https://github.com/advisories/unrelated' }], effects: [], nodes: ['node_modules/other'] };
  r.metadata.vulnerabilities.moderate = 1; r.metadata.vulnerabilities.total++;
  const high = classifyAudit(JSON.stringify(r), 1, verified, 'high');
  assert.deepEqual(high.blocked, []); assert.equal(high.residual[0].name, 'other'); assert.equal(high.residual[0].severity, 'moderate');
  assert.deepEqual(classifyAudit(JSON.stringify(r), 1, verified, 'moderate').blocked, ['other']);
});

for (const severity of ['moderate', 'high', 'critical']) test(`mixed ancestors retain unrelated ${severity} sources`, () => {
  const r = report();
  r.vulnerabilities.consumer.via.push({ name: 'consumer', severity, range: '*', url: 'https://github.com/advisories/unrelated' });
  if (severity === 'critical') {
    r.vulnerabilities.consumer.severity = 'critical';
    r.metadata.vulnerabilities.high--; r.metadata.vulnerabilities.critical++;
  }
  const decision = classifyAudit(JSON.stringify(r), 1, verified, 'high');
  assert.deepEqual(decision.locallyRemediated, ['braces']);
  assert.equal(decision.residual[0].severity, severity);
  assert.equal(decision.residual[0].sources[0].url, 'https://github.com/advisories/unrelated');
  assert.deepEqual(decision.blocked, severity === 'moderate' ? [] : ['consumer']);
  assert.deepEqual(classifyAudit(JSON.stringify(r), 1, verified, 'moderate').blocked, ['consumer']);
});
test('a second advisory on the remediated package is never removed', () => {
  const r = report();
  r.vulnerabilities.braces.via.push({ name: 'braces', severity: 'high', range: '*', url: 'https://github.com/advisories/another-braces-finding' });
  const result = classifyAudit(JSON.stringify(r), 1, verified);
  assert.deepEqual(result.locallyRemediated, []);
  assert.deepEqual(result.blocked, ['braces', 'consumer']);
});
test('unexplained severity inflation and extra graph edges fail closed', () => {
  const inflated = report();
  inflated.vulnerabilities.consumer.severity = 'critical';
  assert.throws(() => classifyAudit(JSON.stringify(inflated), 1, verified), /Unexplained aggregate/);
  const extra = report(); extra.vulnerabilities.braces.effects.push('absent');
  assert.throws(() => classifyAudit(JSON.stringify(extra), 1, verified), /Incomplete reverse/);
});

test('containment follows POSIX and Windows separators, drive and UNC rules', () => {
  for (const [implementation, root, inside, outside] of [
    [posix, '/project', '/project/node_modules/braces', ['/', '/outside', '/project-escape/file', '/project/../outside']],
    [win32, 'C:/project', 'C:/project/node_modules/braces', ['C:/', 'C:/outside', 'C:/project-escape/file', 'C:/project/../outside', 'D:/project/file', '//server/share/file']],
    [win32, 'C:/Project', 'c:/project/node_modules/braces', ['c:/outside']],
    [win32, '//server/share/project', '//server/share/project/node_modules/braces', ['//server/share/outside', '//other/share/project/file', '//server/other/project/file']],
  ]) {
    assert.equal(within(root, inside, implementation), true);
    assert.equal(npmRelative(root, inside, implementation), 'node_modules/braces');
    for (const path of outside) {
      assert.equal(within(root, path, implementation), false, path);
      assert.throws(() => npmRelative(root, path, implementation), /escapes root/);
    }
  }
  assert.equal(within('C:\\project', 'C:\\project\\..\\outside', win32), false);
  assert.equal(npmRelative('C:\\project', 'C:\\project\\node_modules\\braces\\lib\\parse.js', win32), 'node_modules/braces/lib/parse.js');
});

test('symlinked CLI invocation executes verification rather than silently succeeding', () => {
  const root = project();
  const alias = join(root, 'remediation-cli.mjs');
  symlinkSync(cli, alias);
  const failed = run(process.execPath, [alias, 'verify', '--project-root', root], root);
  assert.notEqual(failed.status, 0);
  assert.match(failed.stderr, /Installed bytes differ/);
  applyRemediations(root);
  const passed = run(process.execPath, [alias, 'verify', '--project-root', root], root);
  assert.equal(passed.status, 0, passed.stderr);
  assert.match(passed.stdout, /"operation": "verify"/);
});
