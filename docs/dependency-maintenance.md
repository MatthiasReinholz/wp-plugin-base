# Dependency Maintenance

The inventory in [dependency-inventory.json](dependency-inventory.json) identifies
source pins, lockfiles, trust tiers, and update owners. A scheduled run is healthy
only when each dependency either reports that its supported pin is current or
produces a validated candidate PR. Review failed matrix instances every week;
a green schedule start alone is not evidence of successful maintenance.

## Review Policy

- Review high or critical advisories immediately and document reachability before
  considering an exception. Fix compatible versions first and exercise the affected
  build or runtime. Do not accept an advisory suppression simply because a package
  is a development dependency: parsers, downloaders, and build tools process inputs.
- Keep overrides narrow and versioned. Remove an override when the direct package
  supplies an equivalent patched graph. Major upgrades need a compatibility test,
  not an automatic acceptance of `npm audit fix --force` suggestions.
- For a blocked dependency, record the current pin, latest evaluated release,
  blocking reason, owner, next review date, and a link to the upstream issue in
  the update PR. Exceptions expire after 30 days unless renewed with new evidence.
- Publisher signature checks and reviewed metadata are distinct trust levels.
  Follow the [candidate isolation contract](update-model.md#candidate-isolation-and-recovery)
  for all external tools. Validate any changed upstream signing identity separately.
- Check supported releases at least weekly through Dependabot and the external
  updater. Security fixes should not wait for the normal weekly schedule.
- Audit every npm lockfile listed in the inventory and both Python lockfiles under
  `tools/python-lint-tools/` and `tools/python-semgrep/`. Also audit fresh lint-only,
  Semgrep-only, and combined Python environments after hash-locked installation.
  The installer combines both Python locks in one environment; run `pip check`
  after both installs. File hashes establish artifact integrity, not absence of
  known vulnerabilities.

## Python Tool Lockfiles

Python lint and security tooling requires Python 3.10 or newer. Both input files
explicitly pin `pip` and `setuptools` so lint-only and security-only installations
also replace vulnerable interpreter-bundled packages. Regenerate each lock from its own tool
directory in an isolated compiler environment:

```bash
pip-compile --allow-unsafe --generate-hashes --output-file=requirements.txt requirements.in
```

The `--allow-unsafe` option includes the explicitly requested packaging tools in
the hash-locked output; it does not disable hash verification during installation.
Review every changed pin and retain `--require-hashes` when installing. Audit each
lock with `pip-audit -r requirements.txt`, then audit the packages actually
installed in each supported tool setup. Include supported Python versions in the
compatibility review: compiling on one interpreter does not establish compatibility
with older interpreters.

The Semgrep input bounds `rpds-py<2026` because its 2026 releases require Python
3.11, while 0.30.0 preserves the Python 3.10 floor. Revisit this bound when
intentionally raising that floor or if an advisory requires a newer release.

## Local Tool Installation

Tool selections are validated before the destination changes. A failed candidate
install leaves existing commands usable; partial selections preserve unrelated
commands. Python tool updates carry forward installed lint/security modes, and
`all` continues to leave Semgrep opt-in unless it is already installed.

The installer prepares immutable `.python-tools-venv.*` and `.node-tools.*`
directories, verifies them, then activates individual executable wrappers by
atomic rename. Physical environment paths never move because virtual-environment
scripts embed them. Previous successful environments remain available to running
processes; remove an unused old environment only after its processes finish and
no active wrapper references it. Failed candidate directories are removed.

## PHP Quality Tool Compatibility

The managed quality-tool manifest fixes Composer's resolution platform at PHP
8.0.0, the oldest supported interpreter for this tool bundle. Keep Composer's
runtime platform checks enabled. Installing with a newer Composer container must
not select dependencies that cannot execute under the supported host interpreter.
This tooling floor does not change a plugin's project-owned runtime metadata.

The reviewed lock uses Doctrine Instantiator 1.5.0, PHPStan 2.3.1,
phpstan-wordpress 2.0.4 and PHPUnit 9.6.38. Actual locked installation, platform
checks and quality-tool execution passed on PHP 8.0, including actual Doctrine object instantiation. The full foundation gate
also uses Composer's real solver to reject incompatible locked PHP requirements.

## Runtime-Aligned Major Updates

The admin starters and existing-application fixture externalize React to
WordPress. WordPress 6.9 and 7.1.3 both publish React 18.3.1, so their development
React, React DOM and corresponding type packages must remain on the matching
major until the supported WordPress runtime is deliberately requalified. Dependabot
continues patch/minor checks; standalone React 19 proposals are excluded from
these three directories. Revisit all four packages together with that runtime
migration, rather than updating only React or React DOM.

The existing-application fixture retains TypeScript 6 because its resolved
`typescript-eslint` 8.72.0 parser supports `>=4.8.4 <6.1.0`. A TypeScript 7
upgrade must include a supported parser migration and full fixture qualification;
Dependabot continues compatible compiler updates while excluding standalone major
proposals for this fixture.

Dependabot groups `@wordpress/*` updates per directory (`wordpress-packages`) for
both admin starters and the fixture, because these packages are qualified as a
set; DataViews 20, for example, requires scripts 36.1. Dependabot still opens
one grouped proposal per directory. The foundation contracts require identical
`overrides` and shared `@wordpress/*` and React versions across all three
manifests, so combine the three grouped proposals into one reviewed change.

The Semgrep toolchain supports Python 3.10. Its existing `rpds-py<2026` constraint
is also represented in Dependabot configuration because the calendar-version
2026 releases require Python 3.11. Revisit the bound and automation policy together
when intentionally raising the Python support floor. These compatibility rules do
not suppress advisory scanning or permit vulnerable dependencies.

The required full foundation CI job also installs the pinned scanner and runs
Semgrep's native rule tests against the actual production rule directory and
`tests/fixtures/semgrep/wordpress-security.php`. Every existing rule has an unsafe
case and a checked-permission control. This verifies detection behavior instead
of merely accepting a successful package install. Scanner execution is
qualified on the supported CI runner; a local host whose CPU ISA is below the
scanner binary's requirement cannot substitute for that run.

## Existing Child Projects

Admin source files, `package.json`, and `package-lock.json` are seeded once and
remain child-owned. A foundation update intentionally preserves them. Existing
children must review and merge corresponding manifest changes, regenerate their
own lockfile, run `npm ci`, `npm run build`, and `npm run lint:js`, and test the
rendered admin page. Preserve application-specific dependencies and source changes.
Do not replace a customized child lockfile with the foundation's starter lockfile.

New compatible security overrides can be copied from the matching starter
manifest and merged into the child's existing `overrides` object. Run
`npm install --package-lock-only --ignore-scripts`, review the diff, and audit the
result before installation. The effective admin tooling runtime floor is Node.js 22.22.2 or 24.15.0 in those
LTS series; Node.js 26 and newer also satisfy the declared engines. Align the
child manifest engines and CI runtime with the complete dependency graph.

Keep npm updates enabled for the child-owned package through the managed
Dependabot configuration. Each managed npm entry, root and admin UI, groups
`@wordpress/*` updates (`wordpress-packages`) into one proposal per directory;
existing children receive the group on their next foundation sync. GitLab users
should configure their chosen dependency updater for the same child-owned paths.

### Who Updates Which Dependency

Projects may apply their own dependency updates, and an older foundation never
blocks a project's validation, Plugin Check, packaging or release. GitHub raises
Dependabot alerts for every manifest in a child repository, including files the
child does not own. Where the file lives decides what an update does:

| Path | Project update | Next foundation sync |
| --- | --- | --- |
| Root `composer.*` / `package*.json`, `.wp-plugin-base-admin-ui/package*.json` | Merge it; the project owns these files | Preserved |
| Action pins in managed workflows under `.github/` | Merge it; full-SHA pin updates pass validation | Kept, unless the catalog lists the pin as an older reviewed predecessor |
| Action pins in project-owned workflows | Merge it | Kept; reviewed predecessors are upgraded |
| `.wp-plugin-base/**` (vendored foundation) | Not needed; close the PR | Replaced by the verified foundation release |
| `.wp-plugin-base-quality-pack/`, `.wp-plugin-base-security-pack/` | Not needed; close the PR | Rewritten by managed sync |

Managed workflows stay foundation-owned apart from their action pins. Project
validation compares them with `.wp-plugin-base-automation.json` and accepts a
file whose only change is a full-SHA action pin; any other edit fails. Sync never
downgrades a pin the catalog has not reviewed; reviewed predecessors are
upgraded to the rendered pin. From v1.10.11, generated child Dependabot
configuration ignores no actions, so action version and security updates reach
every workflow. A project that pins an action by hand keeps that pin until it
changes it again. Projects still on v1.10.10 or earlier that edited a managed pin
by hand should restore it before their first update, because the older updater
runs its own ownership check first.

Admin UI dependency updates keep the `braces` backport valid: the remediation is
bound to each installed `braces` copy, not to the whole manifest or lock (see
[npm security remediations](npm-security-remediations.md)). The managed admin
build applies it after `npm ci`, and the starters seed `npm-remediations.json`.
Projects created from earlier starters may keep their
`packageSha256`/`lockfileSha256` fields; they are no longer compared.

Advisories in the quality and security pack tool locks are reported as warnings
in projects, because only a foundation release changes those locks. Foundation
validation blocks on the same advisories. Advisories in project-owned
dependencies still fail the security pack audit at the configured threshold.
Vendored foundation files are replaced on every foundation update, so local
edits there are lost.

## October 21, 2026 Node.js 24 Default And WordPress Environment Review

Following the October 2026 Node.js security releases (24.22.1 and 22.23.4),
foundation CI, the external dependency candidate validator and the child default
move to Node.js 24. Node.js 22 remains supported for projects. Workflows keep
selecting a major version (`'24'`, or `'22'` for the Node.js 22 runtime job), so
setup-node resolves the current security release.

`@wordpress/env` advances from 11.16.0 to 11.17.0 (Dependabot #391), which
resolves the block recorded in the
[October 20 Node tooling review](#october-20-2026-node-tooling-review). That block
was caused by npm's `engine-strict`, not by the code that runs:

- `@wordpress/env` 11.17.0 itself declares Node.js >=18.12.0, like 11.16.0.
- Its `@wp-playground/cli` ^3.1.56 dependency brings `@php-wasm/*` and
  `@wp-playground/*` 3.1.60 packages that declare Node.js >=24.18.0 and
  npm >=11.16.0. They implement the Playground runtime, which `wp-env` resolves
  only when started with `--runtime=playground` and then runs as a separate
  process. The foundation always uses the default Docker runtime.

The tool's `.npmrc` now sets `engine-strict=false`, and the tool manifest keeps
Node.js >=22.12.0 with npm >=10.2.3. `scripts/lib/check_wordpress_env_engines.cjs`
replaces the whole-tree check: before activation, it enforces the tool manifest's
node and npm engines and `engines.node` of every package reachable from
`@wordpress/env` without entering `@wp-playground/cli`, following Node.js module
resolution. A package shared with the Playground runtime is still checked. Ranges
are evaluated as npm does (`semver.satisfies` with prereleases included), using
`semver` 7.8.5, which the tool now declares as an exact-pinned dependency so the
evaluator does not depend on the excluded graph. npm still runs the install script
of the Playground-only `fs-ext-extra-prebuilt` during `npm ci`; it succeeds on
Node.js 22.12. The lock was refreshed from the existing lock with
`npm install --package-lock-only`. Playground
and php-wasm move from 3.1.50 to 3.1.60, with in-range transitive refreshes such
as `fs-ext-extra-prebuilt` 2.2.16 and `fast-xml-parser` 5.11.2.

Both adapted upstream files keep their reviewed SHA-256 digests in 11.17.0, which
still requires `simple-git` ^3.32.3 through the default import. The adaptation
therefore accepts 11.17.0 instead of 11.16.0, and the `simple-git` 4.0.2 override
remains. The `adm-zip`, `ajv` and `tmp` overrides are removed: without them the
11.17.0 graph resolves the same 0.6.1, 8.18.0 and 0.2.7 releases. The `qs` 6.16.0,
`ws` 8.21.3 and `simple-git` 4.0.2 overrides still raise versions their parents
request. `npm audit` reports only the four moderate `sprintf-js` findings already
recorded with a 2026-11-19 review. `@wordpress/env` 12.0.0 is a major release and
is not part of this review.

Engine declarations follow the graphs that run. The npm audit producer
(`>=22.12.0`) and the Markdown tool bundle keep their floors. The admin starters
and the existing-application fixture keep `^22.22.2 || ^24.15.0 || >=26.0.0`, the
range `@wordpress/scripts` 36.1 declares. Those manifests are child-owned seeds
(see [Existing Child Projects](#existing-child-projects)). Configuration
validation keeps accepting any numeric `NODE_VERSION`.

Qualification evidence:

- On Node.js 22.12.0 with npm 10.9.0, `npm ci` of the tool succeeds. npm warns
  only for the 21 `@php-wasm/*` and `@wp-playground/*` packages, `wp-env --version`
  reports 11.17.0, and the engine check passes for the 151 packages the Docker
  runtime can load, none of them from the Playground runtime.
- `test_wordpress_env_engines.cjs` covers Docker-only, Playground-only and shared
  packages, nested resolution, npm aliases, dependency cycles, missing required and
  optional dependencies, the tool manifest's node and npm engines, relative roots
  and the CLI. `check_wordpress_env_tooling.sh` passed on Node.js 22.12.0 and
  24.22.0: high-threshold lock audit, `npm ci`, the engine check, registry
  signatures and the real clone, fetch, branch update and tag checkout test.
- Foundation CI runs Plugin Check and POT generation through the tool on Node.js
  24, and the WordPress runtime matrix starts, uses, stops and cleans up actual
  environments on WordPress 7.1.2 with Node.js 24 and WordPress 6.9 with Node.js 22.

## October 20, 2026 Advisory Review

All twelve open Dependabot advisories were reviewed. Nine are fixed by narrow
overrides. Three have no patched release that their pinned consumers accept and
remain visible.

Both admin starters and the existing-application fixture receive the same four
overrides. `postcss-selector-parser` 7.1.6 replaces the cssnano 6 plugins' copies
with the patched release already used by stylelint and CSS modules for
GHSA-rj75-hqrm-r3gf; the only breaking change listed for 7.0.0 makes insertion
during iteration safe. The key is deliberately unscoped: npm 10 no longer applies
a range-scoped override such as `@^6.0.0` once it moves an edge outside that
range, so `npm ci` rejects the lock. Every copy resolves to 7.1.6 either way. The
in-major 6.1.5 backport published on October 19 is not yet recognized by the
advisory's patched range; once it is, replace this override with
`postcss-selector-parser@^6.0.0` 6.1.5 or remove it. `js-yaml@^5.0.0` advances
markdownlint-cli's copy to 5.4.1, the release markdownlint-cli2 itself pins, for
GHSA-r3ph-w7gj-g6xm. `smol-toml` 1.9.0 matches
the Markdown tool bundle for GHSA-r4xh-jqrq-34v2. The `js-yaml` and `smol-toml`
overrides sit outside markdownlint-cli 0.49.1's declared `~5.2.1` and `~1.7.0`
ranges; remove both when markdownlint-cli adopts patched releases. The fixture
also refreshes `shell-quote` 1.12.0 (GHSA-pqg4-j6r4-53mv) and `source-map-js`
1.2.2 (GHSA-68fv-2mgg-jv7q) to the starters' patched versions; these fixture
findings were not among the twelve alerts. Existing child projects can adopt the
overrides as described in [Existing Child Projects](#existing-child-projects).

`katex` 0.18.10 addresses GHSA-238p-pmpm-9mq7 in the starters, the fixture and the
Markdown tool bundle. markdownlint uses only the math syntax extension, but that
package's entry point also imports its KaTeX-based HTML renderer. KaTeX is
therefore loaded during linting, while `renderToString` is never called, so the
override only has to load outside the declared `^0.16.0` range. Version 0.18.11
is deprecated upstream for unintended breaking changes and 0.19.0 is a breaking
release; neither was adopted. KaTeX 0.18 depends on commander 15, which requires
Node.js 22.12 or newer; the KaTeX CLI that uses it is not invoked. Remove the
override when micromark-extension-math accepts a patched KaTeX range. The Markdown
tool manifest digests were renewed after review; the braces backport still
applies, verifies, and leaves no residual advisory.

Production builds of both starters and the fixture are byte-identical before and
after these changes on Node.js 24. JavaScript lint, the typed-parser contract,
fixture type checks and tests passed. The full repository Markdown lint and a
math-syntax document passed with the updated tool bundle. The remaining starter
and fixture audit finding is the braces 3.0.3 advisory, for which the reviewed
backport is available to child projects as described in
[npm security remediations](npm-security-remediations.md).

GHSA-r7fv-28h4-cvq7, published after this review, affects the `markdown-it`
15.0.1 that markdownlint-cli2 0.23.3 pins exactly in the Markdown tool bundle.
The starters and fixture already resolve the patched 14.3.2 through
markdownlint-cli. markdownlint constructs markdown-it only for custom rules, with
`html` enabled and `typographer` left off. The foundation configures no custom
rules or markdown-it plugins, so it neither loads the parser nor enables the
affected smartquotes rule. The in-major `markdown-it` 15.0.3 override is adopted
anyway. It carries the 15.0.2 fix plus the 15.0.3 fixes for quadratic parsing of
multiline reference definitions, which affect every configuration, and of
unclosed inline HTML constructs, which apply because `html` is enabled. The
override sits outside the CLI's exact pin but keeps the major and public API;
15.0.3 also limits reference labels to 999 code points, which can change the
tokens custom rules receive. Its only other graph change is markdown-it's own
`argparse` advancing to 3.0.3. Remove the override when markdownlint-cli2 pins
`markdown-it` 15.0.3 or newer. The Markdown tool manifest digests were renewed
after review. `npm ci` succeeds on npm 10 and 11, the full repository Markdown
lint passes, the remediation and tool installer tests pass, and the bundle audit
reports only the braces advisory.

Foundation maintainers own the following exceptions. Each expires on 2026-11-19
unless renewed with new evidence, and is removed when upstream publishes a
compatible fix.

- [GHSA-84m7-p3x7-pcfv](https://github.com/advisories/GHSA-84m7-p3x7-pcfv)
  (`mcp` 1.29.0, pinned by Semgrep): Semgrep 1.181.0, the latest release, still
  pins `mcp==1.29.0`; upstream tracks the update in
  [semgrep/semgrep#11992](https://github.com/semgrep/semgrep/issues/11992). The
  advisory affects stateful Streamable HTTP MCP servers. Foundation and child CI
  run Semgrep only as a CLI scanner and rule tester and never start `semgrep mcp`.
- [GHSA-hp3w-g68c-fv3c](https://github.com/advisories/GHSA-hp3w-g68c-fv3c)
  (`sprintf-js` 1.0.3 via `@wordpress/env` 11.16.0): 1.1.3, the latest release, is
  affected; see [alexei/sprintf.js#237](https://github.com/alexei/sprintf.js/issues/237).
  `@wordpress/env` 11.17.0 still requires `js-yaml` 3, which loads `argparse` and
  `sprintf-js` only from its CLI entry point; the WordPress environment tool uses
  the library API.
- [GHSA-vfj7-8cjw-p6xm](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm)
  (`braces` 3.0.3 in the Markdown tool bundle): 3.0.3 is the latest release and
  the maintainer disputes the advisory
  ([micromatch/braces#85](https://github.com/micromatch/braces/issues/85)). The
  verified backport remediates every installed copy before tool activation.

## October 20, 2026 External Tool Review

Syft advances from 1.52.0 to 1.54.1; tag 1.53.0 has no published release. The
checksum manifest's Sigstore bundle verified with the reviewed Cosign 3.1.3
against the exact `anchore/syft` release workflow identity on `refs/heads/main`
and GitHub's OIDC issuer. The certificate's source commit matches the `v1.54.1`
tag, and the Linux amd64, macOS amd64 and macOS arm64 archive hashes match the
signed manifest. The release notes contain cataloger fixes and dependency
updates. They do not change the `dir:` source or `cyclonedx-json` output options
used by SBOM generation.

Syft 1.55.0, published after that candidate, was then reviewed and adopted. Its
checksum manifest's Sigstore bundle verified with the reviewed, hash-pinned
Cosign 3.1.3 against the same release workflow identity and OIDC issuer. The
certificate's source commit `f15c3343e29dfb20cf6d82c820e7090b49808c96` is the
`v1.55.0` tag target, and all three archive hashes match the signed manifest.
The release adds IPK cataloging, records Debian copyright holders in license
data, fixes a panic when the CLI command is constructed repeatedly and pins the
GGUF parser. It remediates five `golang.org/x/net` advisories, four high and one
critical (GO-2026-6612). A `cyclonedx-json` scan of the child template produced
the same specification version and component count as 1.54.1.

Cosign 3.1.4 was then reviewed and adopted. Its `cosign_checksums.txt` Sigstore
bundle verified with the hash-pinned Cosign 3.1.3 against the
`keyless@projectsigstore.iam.gserviceaccount.com` identity and the Google
Accounts issuer, and the Linux amd64, macOS amd64 and macOS arm64 binary hashes
match the signed manifest. The release builds with Go 1.27.3, adds
`cosign bundle create-from-container`, stops `verify` panicking on a bundle
entry without a hash and makes `verify-blob` honour non-SHA256 key hash
algorithms. It does not change the `verify-blob --bundle` identity and issuer
options the release and update verifiers use.

The Composer pin moves to the current official `composer:2` index digest
`sha256:af98f42dfff7c68ba8d53c2164fd9fde1087b7d449514baa38c418b1f6bc4bac`.
It still provides Composer 2.10.3 with PHP 8.5.11. Only the riscv64 manifest was
rebuilt; the amd64 and arm64 manifests are unchanged from the previous pin.
The `composer:2` tag still points to that index, built from the upstream commit
listed in Docker's official image definition.

## October 20, 2026 GitHub Actions Review

The managed action catalog adopts these upstream releases. Each previous pin
becomes a predecessor so child-owned workflows migrate during sync; audit accepts
only the new pins. Every new pin is the commit of its upstream release tag,
resolved through the GitHub API, and matches the Dependabot proposal. This change
supersedes Dependabot PRs #387, #388, #395, #396, #397 and #417, which each updated
only part of the managed workflows and catalog.

| Action | Accepted release | Notes from upstream release notes |
| --- | --- | --- |
| `shivammathur/setup-php` | 2.37.2 to 2.40.0 | Same Node 24 runtime and `action.yml`; adds tool checksum pinning, Ubuntu 26.04 and PHP 8.7 nightly; deprecates Intel macOS and macOS 14 arm64 runners |
| `ossf/scorecard-action` | v2.4.4 to v2.5.0 | Scorecard v5.6.0 after its hosted-service move; upstream says older action versions will fail; workflow checks now follow YAML aliases; no longer prints the token variable |
| `actions/download-artifact` | v8.0.1 to v8.0.2 | `@actions/artifact` 6.3.1 with HTTP 429 `Retry-After` retries; digest-mismatch failure behavior unchanged |
| `actions/upload-artifact` | v7.0.1 to v7.0.2 | `@actions/artifact` 6.3.1 with HTTP 429 retries; inputs and outputs unchanged |
| `actions/setup-node` | v7.0.0 to v7.1.0 | Adds `mise.toml` and absolute `node-version-file` support, Node version validation and manifest fetch retries |
| `github/codeql-action/upload-sarif` | v4.38.2 to v4.39.0 | Minimum CodeQL bundle raised to 2.20.7; default bundle 2.27.2; `upload-sarif` inputs unchanged |

All runtimes remain Node 24, except Scorecard, which runs as a container. No
inputs, outputs or permissions used by the managed workflows changed. Verification
covered the workflow audit, root and child workflow parity, pin migration tests
and release/update fixtures.

## October 20, 2026 WordPress Package Review

The twenty Dependabot proposals for the October 7 WordPress package release were
reviewed as one set. Both admin starters and the existing-application fixture now
pin `@wordpress/api-fetch` 7.57.0, `@wordpress/components` 42.0.0,
`@wordpress/data` 10.57.0, `@wordpress/element` 9.0.0, `@wordpress/i18n` 6.30.0
and `@wordpress/scripts` 36.1.0. The DataViews starter and the fixture also move
to `@wordpress/dataviews` 20.0.0. No major update is held, so no Dependabot ignore
rule was added. Data 10.57 already depends on element 9, so the packages move
together.

The element, components and DataViews majors are listed upstream as "Upgrade React
to v19" ([WordPress/gutenberg#83941](https://github.com/WordPress/gutenberg/pull/83941)).
That change migrates source types. The published packages keep `^18 || ^19` React
peers, and their runtime code supports React 18: `serialize` handles both context
layouts, and the new `@wordpress/react-inert-value` helper checks the React
version. The manifests keep React and React DOM 18.3.1, and WordPress still
supplies React at runtime. `@wordpress/babel-preset-default` 9, required by scripts
36.1, declares `react` ^19.3.0 and installs a nested React 19.3.1 that the preset
never loads. Built bundles still externalize React. Scripts 36.1 declares the same
`^22.22.2 || ^24.15.0 || >=26.0.0` Node engines.

DataViews 20 requires `@wordpress/dependency-extraction-webpack-plugin` 6.57 or
newer, which `@wordpress/scripts` 36.1 supplies. Its bundled code imports
`@wordpress/react-inert-value`. Extraction plugin 6.57 bundles that package, but
older releases map it to a `wp-react-inert-value` script handle that WordPress 7.1
does not register. WordPress then refuses to enqueue the admin script. That is why
the standalone DataViews proposals (#408 and #410) failed the real WordPress
check. Children with a custom webpack configuration or a separately pinned
extraction plugin must ensure version 6.57 or newer. With the aligned set, every
generated `index.asset.php` dependency list is unchanged.

The lock refresh is a full transitive refresh within the declared ranges, not only
the direct packages. It also advances in-range dependencies such as Playwright
1.64.1 and stylelint 17.16. The temporary `typescript-eslint` 8.70.0 override is
removed. `@wordpress/eslint-plugin` 27.1 requires `typescript-eslint` ^8.70.1, so
the override forced a version below that range. The complete 8.72.0 package group
now resolves as one version in every lock and keeps the `typescript >=4.8.4 <6.1.0`
peer.

Qualification evidence:

- `npm ci` and `npm ls --all` passed for all three projects on Node.js 22 with
  npm 10.9 and on Node.js 24 with npm 11.19.
- The advisory review overrides still resolve (`postcss-selector-parser` 7.1.6,
  `js-yaml` 5.4.1, `katex` 0.18.10 and `smol-toml` 1.9.0). `npm audit` reports only
  the existing braces advisory.
- The basic starter build is byte-identical. The DataViews bundle grows from 853 KB
  to 872 KB (196 KB to 200 KB gzip), which remains within its budgets. Node.js 22
  and 24 builds are identical.
- JavaScript lint, the typed-parser contract and the standalone admin form and
  DataViews browser tests passed with Playwright 1.64.1.
- The real WordPress runtime contracts passed on PHP 8.3, including rendering,
  querying and saving the built admin page. The basic starter passed on WordPress
  6.9 and 7.1.2, and the DataViews starter passed on 7.1.2. These runs preceded
  the override removal. Removing the override changes only lint tooling, and
  the starter and fixture builds stayed byte-identical.
- The fixture's type check, lint, unit and runtime tests passed, along with the
  existing-application adoption test.

Existing DataViews children must upgrade DataViews and scripts in one change. See
the [DataViews migration section](../templates/child/admin-ui-pack/docs/admin-ui-pack.md#dataviews-behavior-and-migration)
of the admin UI pack documentation.

## October 20, 2026 Node Tooling Review

The npm audit producer advances `@npmcli/arborist` from 9.9.2 to 9.9.3 (from
Dependabot #418). Upstream changes are two bug fixes: peer-conflict reporting for
load failures and `allowScripts` keys under the linked install strategy. Neither
touches the audit path, and dependencies are unchanged. Node 22 and 24 regenerate
the same lock as Dependabot. The tarball matches its integrity value. Node
22.12.0, 22.23.3 and 24.22.0 install the same 2,151-file tree: 116 packages with
zero self-audit findings and verified registry signatures. No locked package
excludes Node 22.12.0. Only the three changed Arborist files and the hidden
lockfile differ from 9.9.2. An independent recomputation of the inventory digest
reproduced the previous value before recording the new one. On the remediation
fixture and Markdown tool graphs, 9.9.2 and 9.9.3 produce identical raw reports,
and real audits pass under Node 22 and 24.

WordPress environment tooling remains blocked at 11.16.0:

| Field | Value |
| --- | --- |
| Current pin | `@wordpress/env` 11.16.0, `simple-git` override 4.0.2 |
| Latest evaluated | 11.17.0 (Dependabot #391) |
| Reason | 11.17.0 requires `@wp-playground/cli` ^3.1.56, which pins `@php-wasm/*` packages that declare Node >=24.18.0 and npm >=11.16.0 from 3.1.55, so `engine-strict` installation fails on the supported Node 22 floor. |
| Owner | Foundation maintainers |
| Next review | 2026-11-19 |
| Cause | [WordPress/wordpress-playground#4322](https://github.com/WordPress/wordpress-playground/pull/4322) (merged) raised the engine floor; adopt with a deliberate Node 24 floor migration |

The two adapted upstream files are byte-identical in 11.17.0, which still
requires `simple-git` ^3.32.3 through the default import, so the adaptation and
override remain needed. Its expected version was deliberately not refreshed. Adopt
11.17.0 or later only with an explicit Node 24 floor migration, or once a release
restores a Node 22-compatible Playground graph. The `sprintf-js` chain
(GHSA-hp3w-g68c-fv3c, all versions) still has no patched release, so the four
moderate findings remain visible below the high threshold. The `adm-zip`, `ajv`
and `tmp` overrides now equal what their parents already resolve; `qs`, `ws`
and `simple-git` still request older versions. Revisit all six
with the next qualified upgrade instead of changing the retained graph.

## October 20, 2026 Python And PHP Tool Review

Semgrep advances from 1.179.0 to 1.181.0 (from Dependabot #416) and PHPStan from
2.2.17 to 2.3.1 (from Dependabot #389). Both locks were reproduced independently:
Semgrep's dependency metadata is unchanged, so only its own hashes change, and the
PHPStan update changes only that package under the PHP 8.0.0 platform. The PyJWT
2.15.1 dependency and the `rpds-py<2026` support bound are unchanged. Semgrep
1.181.0 still requires exactly MCP 1.29.0, so
[GHSA-84m7-p3x7-pcfv](https://github.com/advisories/GHSA-84m7-p3x7-pcfv) remains a
visible, blocked lock-audit finding until Semgrep accepts a patched MCP release.
Hash-locked Semgrep-only and combined installations pass `pip check` on Python
3.10, and the real scanner detects every rule in the unsafe fixtures. PHPStan 2.3
adds new rules only to bleeding-edge configuration, which the quality pack does not
enable; the managed fixture still analyses cleanly at level 5 on PHP 8.0 and 8.5,
and a deliberate level-5 error is still reported.

## October 9, 2026 Markdown Tooling Review

The latest compatible Markdown CLI still depends on `braces` 3.0.3. Its staged
bootstrap now uses the foundation's canonical integrity-bound depth-limit
backport before activating the tool; no second patch implementation or npm
lifecycle hook is introduced. The raw upstream advisory remains visible, and
read-only qualification verifies the installed bytes and complete advisory graph.
See [the shared remediation contract](npm-security-remediations.md) for provenance,
manifest ownership and removal criteria.

The `smol-toml` override advances from 1.7.1 to the published compatible 1.9.0 fix,
retaining its Node 18+ requirement and the bundle's existing Node floor. The
existing package API and full repository Markdown commands are qualified with
the new lock. Unrelated low-severity KaTeX findings remain visible; this is not a
claim that the complete tool graph has zero raw findings. The October 20, 2026
review resolves the KaTeX finding.

## October 2026 Tooling Maintenance

WordPress environment tooling retains 11.16.0 and its Node 22-compatible
Playground graph, with `simple-git` 4.0.2
explicitly overridden until upstream adopts its security fixes. Version 4 removes
its default CommonJS export. The isolated installer applies the maintained
`scripts/lib/patch_wordpress_env_git.cjs` adaptation to the two upstream imports,
using the supported named export. It verifies exact package versions and both
upstream source SHA-256 digests before writing either file; drift aborts install.
Exact already-adapted bytes are accepted idempotently; unknown versions, changed
bytes and linked inputs are rejected. The installer prepares an isolated sibling
staging directory and activates it only after npm and adaptation both succeed.
It accepts only the private empty directory supplied by its callers; an existing
installation is never overwritten. Failed preparation, including a partial source
write, is discarded without publishing a usable partial tool installation.
No unsafe Git options or global module interception are introduced. Remove the
patch and override together when an upstream release supports patched simple-git.
The real wp-env download implementation is tested with clone, repeated fetch,
branch advancement and tag checkout, plus rejection of modified source files. The refreshed
lock also resolves patched `http-cache-semantics` and `proxy-addr` versions.
This removes the critical and high findings that previously stopped foundation
checks and unrelated dependency candidates. Keep the override scoped to this
isolated development tool; it does not change plugin runtime dependencies.
Qualify actual WordPress environment lifecycle behavior whenever updating it.
An upstream update intentionally blocks until reviewed: a successful dependency
resolution is not compatibility evidence. When upstream fixes its imports, remove
the adaptation and override in one owned change, run the real Git-source tests,
the WordPress runtime and Plugin Check gates, and the unchanged dependency audit.
Do not merely refresh expected hashes to make an unknown release pass. Keep
published foundation releases immutable and adopt the newly qualified release
through normal signed update validation.

The advisory audit still reports moderate findings through upstream `js-yaml` 3
and its `argparse`/`sprintf-js` chain. There is no patched compatible `sprintf-js`
release at this review; the October 20, 2026 review records its reachability.
Retain the existing high-severity failure threshold and track upstream remediation; do not accept npm's suggested downgrade of the
WordPress environment tool to an obsolete major as a security fix. Tooling checks
now retain npm audit, install, and signature-verification diagnostics in CI logs,
so a future finding can be diagnosed without reproducing a silent failure.

Syft changed its publisher signature format to Sigstore bundles. Candidate
preparation verifies the bundle against the same exact release workflow identity
and OIDC issuer before accepting platform checksums. Missing bundles, invalid
signatures, or mismatched archive checksums still fail before pin mutation.

The same maintenance batch also advances the two hash-locked Python installer pins
to pip 26.2.1 and setuptools 84.0.0, and the Semgrep scanner to 1.179.0 with its
compatible PyJWT 2.15.1 dependency. The existing `rpds-py<2026` support bound
remains intact. Qualify the combined locks on the minimum Python 3.10 interpreter
and run the real scanner against unsafe fixtures before release.

## September 25, 2026 Review

The four committed npm bundles were audited against the current npm advisory
service. Compatible fixes address `adm-zip` 0.6.1, `smol-toml` 1.7.1,
`js-yaml` 4.3.2, `svgo` 3.3.5, and `colord` 2.9.4. These replace vulnerable archive,
configuration, SVG, and color parsers. The `js-yaml`, `svgo` and `minimatch` overrides only target
the affected major series, preserving unrelated dependency API contracts. The
minimatch correction retains v3 callers while newer lint consumers receive the
v10 named-export API; a real typed-parser regression covers that boundary. All four
lockfile audits reported zero advisories after the fixes. This result is dated;
repeat audits because advisory data changes independently of source code.

The Python review also addressed all 24 then-open Dependabot advisories affecting
the Semgrep lock. Semgrep 1.163.0 constrained MCP and PyJWT to vulnerable versions,
so the scanner itself was upgraded to 1.178.0. Its compatible graph includes patched
AnyIO, Cryptography, MCP, Pydantic Settings, Starlette, Python Multipart, and PyJWT.
Both Python locks additionally pin pip 26.2 to address
[GHSA-wf93-45jw-7689](https://github.com/advisories/GHSA-wf93-45jw-7689) and
[GHSA-qwm4-qh6w-59xr](https://github.com/advisories/GHSA-qwm4-qh6w-59xr), which were
present in the interpreter-bundled installer. The follow-up review updates
Codespell to 2.4.3. Both locks also pin setuptools 83.0.0 to address
[GHSA-h35f-9h28-mq5c](https://github.com/advisories/GHSA-h35f-9h28-mq5c),
including the older setuptools seeded by Python 3.10 virtual environments.

Both Python lockfile audits and fresh lint-only, Semgrep-only, and combined
environment audits reported zero known vulnerabilities. Hash-locked installations
and `pip check` passed on Python 3.12; the combined installation also passed on
Python 3.14. The actual repository scanner detected all four expected rule IDs in
unsafe fixtures, accepted safe controls, and produced the expected SARIF on both
interpreters. The final combined locks and installer also passed on actual Python
3.10.21: 72 installed packages audited with zero advisories or skipped packages,
all four scanner rule IDs detected unsafe fixtures, and safe controls passed.
Re-run the supported tool bootstrap to apply these locks to an existing local
tool environment.

The external review evaluated and accepted these upstream releases:

| Dependency | Accepted pin | Review basis |
| --- | --- | --- |
| Plugin Check | 2.1.0 | Explicit major review of upstream release notes; existing reviewed author and stabilization period; WordPress readiness fixtures required |
| Plugin Update Checker | 5.7 | Same major; upstream source vendored unchanged; automatic-update metadata remains opt-in |
| EditorConfig Checker | 3.11.3 | Same major; platform archive hashes recorded and installer validation required |
| Syft | 1.55.0 | Exact publisher signature and signed checksum verification for every supported platform |
| Cosign | 3.1.4 | Exact publisher identity and valid Sigstore bundle for every supported platform |
| Composer | Official version 2 image digest | Docker registry digest recorded; compatible composer checks required |
| WordPress environment | 11.16.0 | Actual WordPress start, CLI execution, stop and owned environment cleanup |
| CodeQL Action | 4.38.2 | Official release commit, managed action catalog migration, workflow audit and parity |

ShellCheck 0.11.0, Actionlint 1.7.12, and Gitleaks 8.30.1 were already the latest
supported releases found by their handlers. Pinned versions need not track an
unrelated major release before its compatibility review is complete. No advisory
exception was required for the four audited npm bundles.

The DataViews starter required a deliberate upgrade from 14.3.0 to 19.1.0, with
its direct WordPress packages aligned to that release. The older package used a
private API opt-in removed from later WordPress dependency graphs: a successful
bundle did not prove it could render. The updated graph passes standalone browser
checks for search, sorting, pagination, page resets, and translated status filters,
plus a clean install, production build, JavaScript lint, and advisory audit. Verify
its generated asset dependencies and supported WordPress browser behavior whenever
updating this optional starter. See the [admin pack migration instructions](../templates/child/admin-ui-pack/docs/admin-ui-pack.md#dataviews-behavior-and-migration) before
upgrading child-owned source.

The new artifact download action is pinned to the reviewed commit for 8.0.1,
which uses Node 24 and fails on archive digest mismatches. The updater additionally
checks its own candidate digest from trusted job outputs; neither check substitutes
for the other.
