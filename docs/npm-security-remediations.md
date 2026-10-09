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

Audit evidence uses npm's official `@npmcli/arborist` 9.9.2 audit API and
`npm-audit-report` 7.0.0 JSON reporter, installed as ordinary unbundled dependencies
from `tools/npm-audit`. A small source-owned adapter calls `audit({ fix: false })`
and the official reporter; it does not rewrite findings or implement dependency
resolution. On both qualified immutable consumer graphs, fresh-cache reports
match npm 11.19.0's complete nodes, edges, advisory sources and severities. One
ancestor's aggregate version range differs between the producer versions; that
raw value is retained, not normalized. Registry metadata can also change counts
and suggested fixes between captures. npm 10.9.9 omitted reciprocal advisory
edges and remains unsuitable for this proof. Incomplete reports stay rejected.

The unbundled tool lock resolves patched published dependencies and has zero
self-audit findings at qualification. The direct APIs and every locked dependency
support the retained Node 22.12+ floor. Application installation and builds keep
their existing package manager; ambient npm only bootstraps the locked audit tool.
The adapter receives explicit registry, complete inclusion and workspace options,
so it does not load application or user npm configuration as audit policy.

The security pack installs this tool once into an isolated temporary directory
using its committed integrity lock, with lifecycle scripts and generated bin links
disabled. The adapter loads the explicit physical API package paths. Before code
is loaded, the verifier binds the installed manifest/lock/config and the entire
`node_modules` tree to signed source. The inventory digest hashes the compact JSON
array of sorted `[forward-slash-relative-path, SHA256-of-file-bytes]` pairs; no
files, including bundled dependencies or hidden metadata, are omitted. Extra files,
changed bytes, symlinks and special files fail closed. Both direct package identities
must match their lock entries. Evidence records their actual versions, tarball
URLs, integrity values and the complete lock/tree digests. Audit cache stays inside
the isolated tool directory, which the security pack removes on exit or interruption.

For a standalone audit, use the same bootstrap and pass its explicit directory:

```bash
audit_tools="$(mktemp -d)"
trap 'rm -rf "$audit_tools"' EXIT
source .wp-plugin-base/scripts/lib/wordpress_tooling.sh
wp_plugin_base_install_npm_audit "$audit_tools"
node .wp-plugin-base/scripts/security/npm-remediation.mjs audit \
  --project-root .wp-plugin-base-admin-ui --audit-level high \
  --audit-tools "$audit_tools"
```

Dependabot monitors the tool lock. An update requires renewed real consumer graph,
self-audit and supported-Node qualification plus an independently reviewed inventory
digest; changing only a version or lock must fail verification.

The audit API explicitly includes development, optional and peer dependencies,
sets the project path, disables workspace/global selection and pins the public
npm registry. These settings are independent of inherited omit, production,
workspace and registry defaults. The raw report remains visible. npm report version,
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
