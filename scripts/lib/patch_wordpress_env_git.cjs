// Temporary compatibility patch for @wordpress/env 11.16.0 and simple-git 4.
// Validate every upstream file before writing; remove once upstream uses named imports.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = path.resolve(process.argv[2]);
// Require physical paths before reading package identities or changing source.
function physical(relative) {
  let current = root;
  for (const part of ['', ...relative.split(path.sep)]) {
    if (part) current = path.join(current, part);
    if (fs.lstatSync(current).isSymbolicLink()) throw new Error(`Linked compatibility input: ${current}`);
  }
  return current;
}
const packageRoot = physical(path.join('node_modules', '@wordpress', 'env'));
const readPackage = (name) => JSON.parse(fs.readFileSync(physical(path.join('node_modules', name, 'package.json')), 'utf8'));
if (readPackage('@wordpress/env').version !== '11.16.0' || readPackage('simple-git').version !== '4.0.2') {
  throw new Error('WordPress environment compatibility patch requires reviewed package versions');
}
const patches = [
  ['lib/download-sources.js', '24a477b5fe46da57e56fe7928e28936a3762d08859235074ffa8e645d48e5459'],
  ['lib/runtime/docker/download-wp-phpunit.js', '12fbc30ecb29353c8ec35474abe0809ab7f9815753aff2ec31cfdb3669296c1a'],
].map(([relative, digest]) => {
  const filename = physical(path.relative(root, path.join(packageRoot, relative)));
  const source = fs.readFileSync(filename);
  const before = "const SimpleGit = require( 'simple-git' );";
  const after = "const { simpleGit: SimpleGit } = require( 'simple-git' );";
  const text = source.toString('utf8');
  const pristine = text.includes(after) ? Buffer.from(text.replace(after, before)) : source;
  if (crypto.createHash('sha256').update(pristine).digest('hex') !== digest ||
      !Buffer.from(text).equals(source) || pristine.toString('utf8').split(before).length !== 2) {
    throw new Error(`Unreviewed WordPress environment source: ${relative}; review upstream compatibility before updating`);
  }
  return [filename, Buffer.from(pristine.toString('utf8').replace(before, after))];
});
for (const [filename, source] of patches) {
  if (!fs.readFileSync(filename).equals(source)) fs.writeFileSync(filename, source);
}
