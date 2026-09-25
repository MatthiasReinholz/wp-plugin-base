# Adopt An Existing WordPress Application

Keep the application's architecture and runtime boundaries. An existing plugin
using public WordPress components, DataViews, TypeScript, webpack, its own REST
API, and its own updater does not need an additional component framework or the
optional starter packs.

Import a complete, reviewed, pinned foundation release using the
[verified manual import](manual-foundation-import.md). Keep the canonical plugin
entry point at the project root and retain application-owned `package.json`,
lockfiles, webpack/TypeScript configuration, source, PHP loaders, and test suites.
Do not copy the optional starter's manifests over an existing application.
Review managed metadata such as `.gitignore` and `.editorconfig` separately; these files follow the
foundation ownership contract rather than the application manifest contract.

A configuration can select the native builder while leaving application
boundaries untouched:

```bash
AUTOMATION_PROFILE=local
ADMIN_UI_PACK_ENABLED=false
REST_OPERATIONS_PACK_ENABLED=false
PLUGIN_RUNTIME_UPDATE_PROVIDER=none
BUILD_SCRIPT=tools/build.sh
BUILD_OUTPUTS=build/index.js,build/index.asset.php,build/index.css,build/index-rtl.css,build/licenses.txt
BUILD_OUTPUT_MANIFEST=build/manifest.json
PACKAGE_INCLUDE=existing-application.php,readme.txt,LICENSE,build
```

Retain the usual identity, version, and runtime metadata keys alongside these
settings. The local profile permits managed synchronization and local validation
without publishers or scheduled update workflows. Select the managed hosted
profile deliberately when the project is ready for that automation.

`BUILD_SCRIPT` belongs to the application. It should preserve its typecheck,
lint, client tests and runtime qualification, then build with its existing
webpack configuration. Foundation JavaScript syntax checks do not replace these
checks. Use the WordPress dependency-extraction plugin, keep its generated
`index.asset.php`, and enqueue the recorded dependencies and version in PHP.
Extract WordPress and React host dependencies rather than silently bundling a
second copy. Keep public paths suitable for lazy chunks loaded from the plugin's
installed URL. Include RTL styles and the license notices for all code actually
bundled into the distributable.

Declare concrete required artifacts in `BUILD_OUTPUTS`. A directory alone does
not prove that compilation succeeded. For dynamic filenames such as lazy chunks,
write `BUILD_OUTPUT_MANIFEST` after compilation and license generation:

```json
{
  "schema_version": 1,
  "artifacts": [
    { "path": "build/index.js", "sha256": "<64 lowercase hexadecimal characters>" },
    { "path": "build/details.contenthash.js", "sha256": "<64 lowercase hexadecimal characters>" }
  ]
}
```

This abbreviated example omits other required entries. The actual manifest must
list every regular file under its parent directory except itself, with its exact
SHA-256 digest. Required fixed outputs still belong in `BUILD_OUTPUTS`, so a
mistaken producer cannot declare an incomplete build successful merely by
omitting an artifact from the manifest. Clean-checkout sync validates safe path
containment before outputs exist; post-build validation requires the complete
output contract. Source files are never made optional by declaring generated
artifacts. The manifest's parent directory must contain generated outputs only:
the builder clears that directory before running the application build, and
removes individually declared fixed outputs too. Keep application sources and
license inputs elsewhere. A failed build may leave missing or partial workspace
outputs while the previous verified package generation remains available.

## WordPress compatibility belongs to the application

Retain the application's independently qualified WordPress and PHP minimums.
Turning off the optional admin pack must not rewrite them. The current optional
DataViews starter's WordPress 7.1 minimum describes **that starter's dependency
graph**. It does not establish a new minimum for an existing application that
has independently qualified a different graph on WordPress 6.9. Conversely, a
consumer's reported qualification is not proof that arbitrary newer dependencies
work on 6.9.

For each supported minimum, validate the actual extracted dependencies and API
exports against that WordPress version, render the actual UI in a browser, and
exercise filtering, paging, forms, lazy loading, errors, and RTL. Keep the
dependency lockfile and evidence together. Upgrade public package versions only
when these compatibility checks pass.

## Executable representative fixture

`tests/fixtures/existing-application/` owns a TypeScript application, real public
`@wordpress/components` and `@wordpress/dataviews` imports, a custom webpack
configuration, lazy import, extracted dependency metadata, CSS/RTL outputs,
license asset, manifest producer, typecheck, lint and application tests. Its
pinned graph uses WordPress 7.1 metadata consistently with the current public
packages; it is an integration fixture, not a certification of the consumer's
6.9 application or a substitute for browser testing on a live WordPress runtime.

Run the fixture qualification with:

```bash
bash scripts/foundation/test_existing_application_adoption.sh
```

The test starts without generated outputs, installs the fixture's own lockfile,
syncs and validates through the foundation, checks ZIP membership and lazy assets,
verifies extracted dependencies and RTL content, and asserts that application
manifests, source configuration, test scripts and minimum metadata are unchanged.
No optional runtime packs or component framework are introduced. Dependency
installation needs registry access or a populated npm cache; subsequent local
validation uses the provisioned tools.

The fixture bundles DataViews and its non-extracted dependencies into lazy
chunks. Its license plugin collects the actual bundled modules, including
concatenated modules, and packages their full license notices together with the
application's GPL license. Selected older change-case sibling packages omit the
monorepo's shared MIT license from their npm tarballs; the fixture includes that
same repository's installed shared license. Missing unrecognized licenses fail
the build. Application imports use public APIs; transitive package internals
still contribute host dependencies that need real WordPress qualification.
The compiled-entry test uses host stubs and is an integration smoke test, not a
browser or WordPress runtime qualification. The large DataViews lazy chunk is
also visible in webpack's performance report; applications should set and test
budgets suitable for their actual features.
