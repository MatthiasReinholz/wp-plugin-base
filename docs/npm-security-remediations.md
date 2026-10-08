# Verified npm security remediations

Prefer an official compatible upstream release. When none exists, this foundation
can apply a specific reviewed backport and prove that the installed package is
remediated before qualifying its audit finding. This does not change package
versions, rewrite lock identities, hide raw findings, or lower an audit threshold.
The initial catalog entry is `braces-3.0.3`, addressing
`GHSA-vfj7-8cjw-p6xm`; npm still publishes 3.0.3 as latest at qualification time.

## Trust and ownership

The signed foundation owns one implementation in `scripts/security/` and a finite
catalog of explicitly reviewed remediations. The braces patch and regression test
are byte-identical to the reviewed app-base backport. The catalog records source
commit, upstream patch head, tarball URL/integrity, patch and regression SHA256s,
and complete pristine/patched package file inventories. An additional catalog
entry requires its own source review, integrity evidence, attack/compatibility
regression, exact advisory contract and tests. There is no project-supplied
advisory ignore list or arbitrary patch execution facility.

The application owns `npm-remediations.json` beside its `package.json` and
`package-lock.json`. Its exact schema is:

```json
{
  "schemaVersion": 1,
  "packageSha256": "<SHA256 of the complete package.json>",
  "lockfileSha256": "<SHA256 of the complete package-lock.json>",
  "remediations": ["braces-3.0.3"]
}
```

Use `sha256sum package.json package-lock.json` after reviewing the final files.
Lock or manifest changes invalidate qualification until their changes and the
installed graph have been reviewed again. Unknown fields/IDs, duplicate IDs,
unsupported versions or changed catalog artifacts fail closed. Do not regenerate
these digests automatically in install or audit jobs.

## Installation and verification

For a child-owned admin UI manifest, add this explicit lifecycle step (compose it
with any existing lifecycle command instead of overwriting application behavior):

```json
{
  "scripts": {
    "postinstall": "node ../.wp-plugin-base/scripts/security/npm-remediation.mjs apply --project-root ."
  }
}
```

Then qualify a clean `npm ci --include=dev --include=optional --include=peer`,
rebuild tracked assets and run the application's tests. The standard admin build
already runs `npm ci`, so its lifecycle applies the backport before compilation.
Other project layouts must use the correct relative path to their signed vendor.
`--ignore-scripts` leaves a pristine installation, which read-only verification
rejects. The CLI requires Node.js, npm and Git; it performs no Git network writes.

`apply` checks every manifest, package identity, lock identity, installed physical
copy and patch applicability before the first write. It accepts only exact
pristine or already-patched inventories, verifies every resulting file and runs
the real depth-attack and unchanged-semantics regression against every copy.
Repeated application is idempotent. A failed installation must be discarded and
recreated with `npm ci`; no partial application is accepted as verified.

`verify` and `audit` never modify package files. Workspaces, package symlinks,
provenance symlinks, escaped/duplicate physical directories and unsupported hidden
installation layouts are rejected. Nested npm dependency directories are
inventoried separately; arbitrary extra files inside the target package are
rejected. The only supported build cache is
`.cache/babel-loader/<64 lowercase hexadecimal characters>.json.gz`, consisting
of regular files. Other cache layouts, manifests, directories and links are
rejected. Cache contents are application build data, outside the npm package
inventory; this path contract is not a general executable-content classifier.
Containment uses native path separators and rejects drive/UNC escapes; npm lock,
audit and inventory keys are normalized to forward slashes on every platform.
CLI entrypoint identity compares physical module paths, so case or symlink aliases
cannot silently skip a command; importing the module does not execute the CLI.
An npm v3 lockfile and the complete installed dependency graph are
required. Do not qualify a production-only installation of an admin toolchain.

## Audit integration

The security pack detects the explicit manifest in a root or admin UI npm
project and calls the canonical read-only audit verifier. Projects without it
continue their existing audit path. A remediation-enabled root project is audited
with its complete installed development graph as well, even though the ordinary
root audit defaults to production dependencies. The caller's configured severity
threshold is preserved.

The audit command explicitly includes development, optional and peer dependencies,
sets the project prefix, disables workspace/global selection and pins the public
npm registry. These CLI settings override inherited omit, production, workspace
and registry defaults. The raw report remains visible. npm report version,
exit status, counts, severity consistency, every dependency edge in both
directions, cycles and exact affected-node coverage are checked. Each raw node's
severity must equal the maximum of its complete source edges. Only the exact
byte-verified catalog advisory source is removed from that graph. Ancestors with
no residual sources qualify fully; mixed ancestors retain the maximum severity
of every remaining source. Output preserves their original aggregate severity,
residual severity and source identities. An unrelated high or critical source
still blocks, including a second advisory on the patched package. Unknown
findings remain visible and block at the caller's threshold. Unexplained severity,
malformed or incomplete reports always fail closed.

`node --test scripts/foundation/test_npm_remediation.mjs` installs a small pinned
real fixture in a temporary directory and exercises attacks, source/lock drift,
multiple physical copies, symlink rejection, audit graphs, thresholds and hostile
npm defaults. The required full foundation suite runs this test. Dependabot
monitors the fixture so an upstream release is visible, but a version change must
be reviewed together with the remediation lifecycle.

## Removal

When an official compatible release fixes the advisory, qualify that release in
the application, remove the corresponding lifecycle invocation and project
manifest, and rerun the normal raw audit and application tests. Remove a catalog
entry only after supported consumers have migrated; retain historical release
provenance. A changed upstream advisory contract requires renewed review rather
than a broader match.

Patch preflight and application set Git's work tree explicitly to the verified npm
project root. This supports nested admin projects inside ordinary or linked Git
worktrees as well as standalone projects. Inherited Git environment variables are
removed before execution, and exact installed-byte verification remains required
after application; a successful Git exit alone is never accepted as patch proof.
