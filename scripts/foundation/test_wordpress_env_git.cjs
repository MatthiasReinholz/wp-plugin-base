// Exercise the installed wp-env implementation, including repeat fetches.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const root = path.resolve(process.argv[2]);
const patch = path.resolve(__dirname, '../lib/patch_wordpress_env_git.cjs');
const first = path.join(root, 'node_modules/@wordpress/env/lib/download-sources.js');
const second = path.join(root, 'node_modules/@wordpress/env/lib/runtime/docker/download-wp-phpunit.js');
const originalFirst = fs.readFileSync(first);
const originalSecond = fs.readFileSync(second);
try {
  fs.appendFileSync(second, '\n// Unreviewed source drift\n');
  assert.throws(() => execFileSync(process.execPath, [patch, root], { stdio: 'pipe' }));
  assert.deepEqual(fs.readFileSync(first), originalFirst, 'Reject all source drift before any write');
} finally {
  fs.writeFileSync(second, originalSecond);
}
execFileSync(process.execPath, [patch, root], { stdio: 'pipe' });
const { downloadGitSource } = require(path.join(root, 'node_modules/@wordpress/env/lib/download-sources.js'));
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'wp-env-git-'));
const upstream = path.join(temporary, 'upstream');
const clonePath = path.join(temporary, 'clone');
const git = (...args) => execFileSync('git', ['-C', upstream, ...args], { stdio: 'pipe' });

(async () => {
  fs.mkdirSync(upstream);
  git('init', '--initial-branch=main');
  git('config', 'user.name', 'Fixture');
  git('config', 'user.email', 'fixture@example.test');
  const source = { url: upstream, clonePath, ref: 'main' };
  const progress = [];
  const options = { onProgress: (value) => progress.push(value), debug: false };
  for (const content of ['initial', 'updated']) {
    fs.writeFileSync(path.join(upstream, 'content.txt'), content);
    git('add', 'content.txt');
    git('commit', '-m', content);
    await downloadGitSource(source, options);
    assert.equal(fs.readFileSync(path.join(clonePath, 'content.txt'), 'utf8'), content);
    assert.equal(progress.at(-1), 1);
  }
  git('tag', 'fixture-tag');
  await downloadGitSource({ ...source, ref: 'fixture-tag' }, options);
  assert.equal(execFileSync('git', ['-C', clonePath, 'rev-parse', 'HEAD'], { encoding: 'utf8' }),
    git('rev-parse', 'fixture-tag').toString());
  console.log('Installed wp-env clone, fetch, branch update and tag checkout passed.');
})().catch((error) => { console.error(error); process.exitCode = 1; })
  .finally(() => fs.rmSync(temporary, { recursive: true, force: true }));
