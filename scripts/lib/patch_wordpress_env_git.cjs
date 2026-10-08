// Temporary compatibility patch for @wordpress/env 11.16.0 and simple-git 4.
// Validate every upstream file before writing; remove once upstream uses named imports.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.resolve(process.argv[2]);
const packageRoot = path.join(root, 'node_modules/@wordpress/env');
const readPackage = (name) => JSON.parse(fs.readFileSync(path.join(root, 'node_modules', name, 'package.json'), 'utf8'));
if (readPackage('@wordpress/env').version !== '11.16.0' || readPackage('simple-git').version !== '4.0.2') {
  throw new Error('WordPress environment compatibility patch requires reviewed package versions');
}
const patches = [
  ['lib/download-sources.js', '24a477b5fe46da57e56fe7928e28936a3762d08859235074ffa8e645d48e5459'],
  ['lib/runtime/docker/download-wp-phpunit.js', '12fbc30ecb29353c8ec35474abe0809ab7f9815753aff2ec31cfdb3669296c1a'],
].map(([relative, digest]) => {
  const filename = path.join(packageRoot, relative);
  const source = fs.readFileSync(filename, 'utf8');
  if (crypto.createHash('sha256').update(source).digest('hex') !== digest) {
    throw new Error(`Unreviewed WordPress environment source: ${relative}`);
  }
  const before = "const SimpleGit = require( 'simple-git' );";
  if (source.split(before).length !== 2) {
    throw new Error(`Unexpected simple-git import: ${relative}`);
  }
  return [filename, source.replace(before, "const { simpleGit: SimpleGit } = require( 'simple-git' );")];
});
for (const [filename, source] of patches) fs.writeFileSync(filename, source);
