# Local development and generated outputs

`AUTOMATION_PROFILE=managed` is the unchanged default. Set
`AUTOMATION_PROFILE=local` to synchronize local tooling and applicable runtime packs
without foundation-owned hosted CI, publishing, dependency-update schedules, release
preparation or deployment. `AUTOMATION_PROVIDER` still describes the repository host;
foundation release-source verification and runtime updater selection are independent.
The local profile does not require hosting credentials. Direct hosted publication and
automated update entrypoints reject it even when credentials are present.

Run `bash .wp-plugin-base/scripts/update/sync_child_repo.sh`, then
`bash .wp-plugin-base/scripts/ci/validate_project.sh`. Keep the project's own typecheck,
unit tests and compatibility checks: foundation syntax checks do not compile TypeScript
or replace application tests. When readiness is enabled, run
`bash .wp-plugin-base/scripts/ci/validate_wordpress_readiness.sh --purpose development`
for experimental metadata such as `1.2.0-beta.1`. This retains matching plugin/readme/npm
versions, metadata, Plugin Check, and enabled quality/security checks. It does not certify
release eligibility. The default purpose is `release`, with stable metadata requirements;
publication/tag policy remains unchanged. Tool installation, WordPress containers and
registry vulnerability audits can need networking; local-only does not mean that missing
security tools or unavailable registries are silently accepted.

## Switching automation profiles

Sync records exact hashes of foundation-owned hosted automation in
`.wp-plugin-base-automation.json`. Commit this managed receipt alongside generated files.
It is excluded from install packages. On a profile/provider switch, sync removes only
recorded, unchanged automation files. Locally changed managed files or application files
that collide with the next profile fail before sync changes anything. Preserve those
changes in application-owned workflow filenames, then restore the last synchronized
bytes or explicitly remove the conflicting path and retry. Do not edit receipt hashes to
conceal a conflict. Repeated sync in either profile is idempotent.

Before replacing the vendor tree in a legacy managed project, run the reviewed new
`capture_automation_ownership.sh` helper from an external trusted foundation checkout,
with `WP_PLUGIN_BASE_ROOT` pointing at the application. It reads the application's
**old** vendored templates and current config, verifies byte-identical hosted outputs,
and writes only the ownership receipt. The automated updater performs this capture
before replacing the vendor tree. Modified automation must be reconciled explicitly;
the helper never claims ownership from filenames alone.

For the first update after a pre-receipt release, sync can reconstruct the prior tracked
vendor templates/config from the application's Git `HEAD` and render them with the
current trusted renderer. Published v1.8.3 and v1.9 formatting are qualified: a
trusted data-only reconstruction recognizes raw placeholders and the static Dependabot
policy only when the captured configuration pins v1.8.3 and all reviewed hosted-template
SHA-256 values match that published tree. Modern or modified template generations cannot
use this legacy format to claim customized files. Only exact matches establish ownership; historical scripts are never
executed. Normal sync always emits current escaping and the current action catalog.
Other historical generator formats or changed action catalogs can require explicit
reconciliation; approximate matches never establish ownership. If that evidence is
unavailable or outputs were customized, restore the prior verified vendor/config and
reconcile those files before capturing ownership.

For pre-receipt repositories, byte-identical rendered templates can establish ownership;
other hosted files remain application-owned and are preserved. Review existing workflows
when first adopting the local profile: an unknown historical workflow cannot safely be
classified from its filename. Local mode does not disable application-owned automation.

## Generated output contract

Declare exact generated regular files, not just an output directory:

```dotenv
BUILD_SCRIPT=scripts/build.sh
BUILD_OUTPUTS=build/index.js,build/index.asset.php,build/index.css,build/index-rtl.css,build/licenses.txt
PACKAGE_INCLUDE=example.php,readme.txt,build
```

Sync adds root-anchored generated-output entries to the managed `.gitignore`. The
manifest parent is ignored as a whole; other declared artifacts are ignored individually.

Only declared generated files and their missing ancestors can be absent during sync and
configuration validation. Main plugin, readme and custom build scripts remain required
sources. The managed admin starter retains its first-sync script bootstrap exception;
its script must exist before execution. Inputs and outputs must remain inside the
repository. Generated paths reject traversal, symbolic links and reserved foundation,
source and package-generation destinations, before and after executing the build.

Under the package lifecycle lock, the builder removes the declared generated files before
running `BUILD_SCRIPT` once. A successful build must recreate every required artifact.
This prevents stale files from making an incomplete build pass. Successful prior package
generations remain available if a new build fails. Workspace build outputs may be absent
or partially regenerated after failure; rerun the application build before using them.
Other undeclared output files are the application build's responsibility unless an
artifact manifest is configured.

For hashed chunks or additional generated assets, also declare:

```dotenv
BUILD_OUTPUT_MANIFEST=build/manifest.json
```

This declares the manifest's entire parent directory (`build/`) as disposable, exclusively
generated output. The builder clears it before building. Do not put source files there.
The build must produce this JSON shape, with repo-relative paths and lowercase SHA-256:

```json
{
  "schema_version": 1,
  "artifacts": [
    { "path": "build/index.js", "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" }
  ]
}
```

Include every regular file under the manifest directory except the manifest itself,
including lazy chunks, extracted dependency metadata, styles, RTL and license assets.
The validator rejects duplicate paths/keys, unsupported schema fields, missing files,
extra unlisted files, altered digests, unsafe paths and symlinks. Fixed `BUILD_OUTPUTS`
remain necessary to specify known entrypoints the producer must not omit. The application
must derive the inventory from its bundler graph and test runtime chunk/dependency loading;
the foundation does not infer webpack's dependency graph from JavaScript. Validation repeats
against the final staged package, so exclusions cannot silently drop declared artifacts.
