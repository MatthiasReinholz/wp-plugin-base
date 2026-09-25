/** Exercise the real parser API used by child-owned typed lint configurations. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { createRequire } = require("node:module");

const installDir = path.resolve(process.argv[2]);
const packageRequire = createRequire(path.join(installDir, "package.json"));
const parser = packageRequire("@typescript-eslint/parser");
const fixture = fs.mkdtempSync(
  path.join(os.tmpdir(), "wp-base-admin-toolchain-"),
);

try {
  fs.mkdirSync(path.join(fixture, "included"));
  fs.writeFileSync(path.join(fixture, "included/index.ts"), "export {};\n");
  fs.writeFileSync(
    path.join(fixture, "tsconfig.json"),
    JSON.stringify({ include: ["included/**/*.ts"] }),
  );
  const code = 'export const value: string = "example";';
  const options = {
    filePath: path.join(fixture, "outside.ts"),
    tsconfigRootDir: fixture,
    projectService: { allowDefaultProject: ["outside.ts"] },
  };
  const result = parser.parseForESLint(code, options);
  assert.equal(result.ast.type, "Program");
  assert.ok(result.services.program.getSourceFile(options.filePath));
  assert.throws(
    () =>
      parser.parseForESLint(code, {
        ...options,
        filePath: path.join(fixture, "not-allowed.ts"),
      }),
    /not found by the project service/,
  );
  console.log("Admin toolchain default-project parser contracts passed.");
} finally {
  fs.rmSync(fixture, { recursive: true, force: true });
}
