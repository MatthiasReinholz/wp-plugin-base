"use strict";

// Executed both by tooling CI and the dependency-audit integrity verifier.
const assert = require("node:assert/strict");
const path = require("node:path");
const braces = require(path.resolve(process.argv[2]));
let assertions = 0;
const check = (fn) => {
  fn();
  assertions++;
};
const methods = ["parse", "compile", "expand", "stringify", "create"];

for (const pattern of [
  "{".repeat(101) + "x" + "}".repeat(101),
  "{".repeat(101) + "x",
  "(".repeat(101) + "x" + ")".repeat(101),
  "({".repeat(51) + "x" + "})".repeat(51),
]) {
  for (const method of methods) {
    check(() => assert.throws(() => braces[method](pattern), /Input depth .*exceeds max depth/));
  }
  check(() => assert.throws(() => braces(pattern), /Input depth .*exceeds max depth/));
}

function ast(depth) {
  const root = { type: "root", nodes: [] };
  let parent = root;
  for (let i = 0; i < depth; i++) {
    const child = { type: "paren", nodes: [], parent };
    parent.nodes.push(child);
    parent = child;
  }
  parent.nodes.push({ type: "text", value: "x", parent });
  return root;
}

for (const method of ["compile", "expand", "stringify"]) {
  check(() => assert.doesNotThrow(() => braces[method](ast(100))));
  check(() => assert.throws(() => braces[method](ast(101)), /AST depth .*exceeds max depth/));
  check(() =>
    assert.throws(() => braces[method](ast(2), { maxDepth: 1 }), /AST depth .*exceeds max depth/),
  );
  const cycle = { type: "root", nodes: [] };
  cycle.nodes.push(cycle);
  check(() => assert.throws(() => braces[method](cycle), /AST depth .*exceeds max depth/));
}

const parentCycle = ast(1);
parentCycle.nodes[0].parent = parentCycle.nodes[0];
check(() => assert.throws(() => braces.expand(parentCycle), /AST parent depth exceeds max depth/));

for (const method of methods) {
  for (const maxDepth of [1.5, -1, Infinity, NaN, "2", null, true]) {
    check(() =>
      assert.throws(
        () => braces[method]("{a,b}", { maxDepth }),
        /maxDepth must be a non-negative finite integer/,
      ),
    );
  }
  check(() => assert.doesNotThrow(() => braces[method]("(".repeat(100) + "x" + ")".repeat(100))));
  check(() =>
    assert.throws(
      () =>
        braces[method]("(".repeat(101) + "x" + ")".repeat(101), {
          maxDepth: 1000,
        }),
      /exceeds max depth/,
    ),
  );
  check(() =>
    assert.throws(
      () => braces[method]("{a,{b,c}}", { maxDepth: 1 }),
      /Input depth .*exceeds max depth/,
    ),
  );
  check(() => assert.doesNotThrow(() => braces[method]("{a,b}", { maxDepth: 1 })));
  check(() =>
    assert.throws(
      () => braces[method]("{a,b}", { maxDepth: 0 }),
      /Input depth .*exceeds max depth/,
    ),
  );
  check(() => assert.doesNotThrow(() => braces[method]("plain", { maxDepth: 0 })));
  // Escaped, bracketed and quoted delimiters are literals, not nesting.
  check(() =>
    assert.doesNotThrow(() => braces[method]("\\{".repeat(200) + "x" + "\\}".repeat(200))),
  );
  check(() => assert.doesNotThrow(() => braces[method]("[" + "{".repeat(200) + "]")));
  check(() => assert.doesNotThrow(() => braces[method]('"' + "{".repeat(200) + '"')));
}

check(() =>
  assert.deepEqual(braces.expand("src/{api,web}/**/*.{ts,tsx}"), [
    "src/api/**/*.ts",
    "src/api/**/*.tsx",
    "src/web/**/*.ts",
    "src/web/**/*.tsx",
  ]),
);
check(() => assert.equal(braces.compile("file-{01..03}.{js,ts}"), "file-(0[1-3]).(js|ts)"));
check(() => assert.deepEqual(braces.expand("{a,{b,c}}"), ["a", "b", "c"]));
check(() =>
  assert.deepEqual(braces(["{a,b}", "{b,c}"], { expand: true, nodupes: true }), ["a", "b", "c"]),
);
// PR72 changed parent propagation here; preserve published stringify behavior.
check(() => assert.equal(braces.stringify("{1..8}", { escapeInvalid: true }), "{1..8}"));
check(() => assert.equal(braces.stringify("{literal}", { escapeInvalid: true }), "{literal}"));
check(() => assert.equal(braces.stringify("${a,b}", { escapeInvalid: true }), "${a,b}"));
check(() => assert.throws(() => braces.expand("{1..10000}"), /range limit/));
console.log(`braces depth/compatibility regressions passed (${assertions} assertions)`);
