'use strict';

const assert = require('node:assert/strict');
const path = require('node:path');

const picomatch = require(path.resolve(process.argv[2]));
const patterns = ['+(*)', '+(*a)', '*(*a)', '+(a*)', '+(a*b)', '*(*.js)'];

// Check the generated structure before exercising the upstream security cases.
for (const pattern of patterns) {
  assert(!/\)[+*]/.test(picomatch.makeRe(pattern).source), pattern);
}
for (const pattern of ['+(*a)', '*(*a)', '+(*a)c', 'x+(*a)']) {
  assert.equal(picomatch.isMatch('a'.repeat(50) + 'b', pattern), false);
}
for (const [value, pattern, expected] of [
  ['abc', '+(*)c', true],
  ['aaa', '+(*a)', true],
  ['a.a', '+(*a)', true],
  ['ab', '+(*a)', false],
  ['axbayb', '+(a*b)', true],
  ['axbay', '+(a*b)', false],
  ['foo.js', '*(*.js)', true],
  ['foo.ts', '*(*.js)', false],
  ['docs/security-model.md', 'docs/**/*.md', true],
  ['templates/child/README.md', 'templates/**/*.md', true],
  ['docs/source.js', '**/*.md', false],
  ['src/index.tsx', '**/*.{js,ts,tsx}', true],
  ['node_modules/a/index.js', '**/node_modules/**', true],
]) {
  assert.equal(picomatch.isMatch(value, pattern), expected, pattern);
}
assert.equal(
  picomatch.isMatch('', '*(*a)', { dot: true }),
  picomatch.isMatch('', '*(*a)', { dot: true, maxExtglobRecursion: false })
);
console.log('Picomatch upstream extglob and consumer compatibility regressions passed.');
