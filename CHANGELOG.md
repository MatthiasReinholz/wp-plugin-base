# Changelog

## v1.10.13

* Update the managed WordPress environment tooling to `@wordpress/env` 11.17.0 without raising the Node.js floor. Its Playground runtime packages declare Node.js 24.18 but are loaded only for `wp-env --runtime=playground`, which the foundation never uses. npm's whole-tree `engine-strict` is replaced by an explicit check of the tool manifest's engines and every package the Docker runtime loads. The redundant `adm-zip`, `ajv` and `tmp` overrides are removed.
* New projects default to `NODE_VERSION=24`, and foundation CI runs on Node.js 24. Node.js 22 remains supported and qualified with a real WordPress environment; existing projects keep their configured runtime and need no change.

## v1.10.12

* Read workflow sources as UTF-8 when rewriting action pins, so sync migration and the managed-workflow pin check keep working under a C/POSIX locale (minimal runner images, GitLab runners without `LANG`) when non-ASCII text precedes a `uses:` reference.

## v1.10.11

* Let projects apply their own dependency updates without breaking validation, Plugin Check, packaging or release. Project validation accepts any full-SHA action pin, including a Dependabot update in a managed workflow; every other managed-workflow edit still fails. Sync keeps project pins on every later sync, upgrades reviewed predecessors and never downgrades. The foundation's own workflow audit still requires reviewed pins.
* Generated child Dependabot configuration no longer ignores actions, so action version and security updates reach every workflow. Earlier vendored templates still render their original bytes during ownership recovery.
* Bind npm remediations to each installed package copy instead of whole `package.json`/`package-lock.json` digests, so project dependency updates keep the reviewed `braces` backport valid. Existing manifests with digests keep working. Other versions or removed packages are left to npm audit, and an advisory is waived only when every affected copy is verified. The managed admin build applies the backport, and both starters seed it, so new admin UI projects pass the security pack audit.
* Report advisories in the foundation-owned quality and security pack tool locks as warnings in projects instead of failing their CI; foundation validation still blocks on them.
* Resolve the critical `certifi` advisory (GHSA-6q48-6c7w-9gw2) in the Semgrep tooling, and the `follow-redirects`, `launch-editor` and `markdown-it` advisories in both admin starters, within their existing ranges. Starters are child-owned: existing projects receive these through their own Dependabot.
* Update signature-verified Cosign 3.1.4.

## v1.10.10

* Override `markdown-it` to 15.0.3 in the Markdown tool bundle for GHSA-r7fv-28h4-cvq7; markdownlint-cli2 0.23.3 pins the affected 15.0.1 exactly. The foundation configures no markdown-it custom rules, and 15.0.3 also carries the quadratic reference-definition and inline HTML parsing fixes. Remediation digests are renewed; the admin starters and fixture already resolve the patched 14.3.2.
* Update signature-verified Syft 1.55.0, which remediates five `golang.org/x/net` advisories including one critical. CycloneDX SBOM output is unchanged.
* Group `@wordpress/*` updates (`wordpress-packages`) in every generated child Dependabot npm entry, root and admin UI, so shared WordPress package releases arrive as one proposal per directory. Existing children receive the group on their next foundation sync, including children upgrading from v1.9.x without an ownership receipt: earlier vendored templates still render their original bytes during ownership recovery.
* Fail closed when a child Dependabot template contains unsupported additions or renders output that does not match the selected update policies.

## v1.10.9

* Resolve nine compatible npm advisories in both admin starters and the existing-application fixture with narrow overrides: `postcss-selector-parser` 7.1.6, `js-yaml@^5.0.0` 5.4.1, `smol-toml` 1.9.0 and `katex` 0.18.10. The Markdown tool bundle adopts the same KaTeX release with renewed remediation digests; starter production builds are byte-identical.
* Update both admin starters to the October 2026 WordPress package set: `@wordpress/components` 42, `@wordpress/element` 9, `@wordpress/dataviews` 20 and `@wordpress/scripts` 36.1, with matching api-fetch, data and i18n releases. React and React DOM remain 18.3.1, and generated `index.asset.php` dependency lists are unchanged.
* DataViews 20 requires `@wordpress/dependency-extraction-webpack-plugin` 6.57 or newer, normally supplied by `@wordpress/scripts` 36.1. Older extraction emits a `wp-react-inert-value` handle that WordPress 7.1 does not register, so WordPress refuses to enqueue the admin script. Upgrade DataViews and scripts in one change, including in custom webpack setups.
* Admin starter files are child-owned and sync does not update them. Existing children should copy the new package versions and overrides from the foundation seeds, remove any copied `typescript-eslint` 8.70.0 override, regenerate the lockfile, and rerun install, build and lint. Import DataViews styles through an entry-level stylesheet: a direct `@wordpress/dataviews/build-style/style.css` import becomes an unregistered script dependency.
* Adopt reviewed GitHub Actions releases: setup-php 2.40.0, scorecard-action 2.5.0, download-artifact 8.0.2, setup-node 7.1.0, upload-artifact 7.0.2 and codeql-action/upload-sarif 4.39.0. Foundation sync migrates managed and child-owned workflows from the previous pins; the workflow audit rejects all other pins.
* Update signature-verified Syft 1.54.1, the `composer:2` image digest, Semgrep 1.181.0, quality-pack PHPStan 2.3.1, and the locked npm audit producer `@npmcli/arborist` 9.9.3 with a renewed inventory digest. Audit thresholds, scanner rules and runtime requirements are unchanged.
* Keep the WordPress environment tool's staging directory cleanup reliable under macOS bash 3.2, and require aligned overrides, `@wordpress/*` and React versions across the admin seeds and fixture, with grouped Dependabot updates for those packages.
* Keep `@wordpress/env` at 11.16.0: 11.17.0 requires WordPress Playground releases that declare Node 24.18, above the supported Node 22 floor. Three advisories without an accepted fix remain documented with reachability and a 2026-11-19 review date: `mcp` (pinned by Semgrep, CLI-only use), `sprintf-js` (no patched release) and `braces` (remediated by the existing verified backport).

## v1.10.8

* Add an explicit GitHub plugin attestation setting for private repositories without Enterprise Cloud. The default remains enabled.
* Preserve mandatory package signing, signing identity verification, SBOMs, immutable payload checks, and foundation source provenance across all release paths.
* Test configuration validation and release workflow boundaries, and document historical-tag recovery behavior.

## v1.10.7

* Qualify WordPress tooling in an isolated staging directory before atomic activation. Reject unknown dependency versions, source drift and linked inputs; accept exact previously adapted bytes idempotently without changing the existing compatibility transformation. Preserve existing installations and test failed preparation, activation conflicts and actual Git operations.
* Publish the previously merged Markdown tooling qualification: apply the existing reviewed braces backport before wrapper activation, retain failed-install recovery, and update compatible smol-toml to 1.9.0. Keep published releases immutable and require explicit upstream-fix retirement review.
* Keep audit producer major upgrades gated on runtime and evidence requalification while retaining patch/minor monitoring and unchanged audit thresholds.

## v1.10.6

* Acquire remediation audit evidence through integrity-locked official npm Arborist and report APIs. Complete advisory graphs no longer depend on the ambient npm CLI version; the existing strict classifier, raw findings and configured thresholds remain unchanged.
* Isolate audit tooling and cache, verify its complete installed file inventory before loading code, and retain the Node 22 runtime floor. Qualify both real consumer graphs, hostile configuration, producer drift and unsupported links; monitor the public tool lock with Dependabot.

## v1.10.5

* Bind npm patch preflight and application to the verified project work tree. Nested admin projects inside Git checkouts no longer silently skip patch paths; exact installed-byte verification remains mandatory.
* Remove inherited Git environment variables case-insensitively, including Windows spellings. Qualify real linked-worktree, nested-project and standalone installs, hostile Git context, and idempotent application without changing catalog artifacts, package versions or audit policy.

## v1.10.4

* Add an explicit, integrity-bound npm backport catalog with one canonical installer and a separate read-only audit verifier. Verify all physical package copies, exact source/lock bytes and security regressions before qualifying an advisory.
* Qualify the reviewed braces 3.0.3 depth-limit backport without changing package versions or audit thresholds. Preserve raw findings and compute residual advisory severity from complete verified dependency paths; unrelated findings and malformed reports fail closed.
* Integrate opt-in, hash-bound application manifests with the security pack and required full-suite regression coverage, including hostile npm configuration, mixed advisories and hidden package rejection.
* Refresh compatible PHPStan 2.2.17, PHPUnit 9.6.38 and basic-starter source-map-js 1.2.2 lock records while retaining existing runtime requirements.

## v1.10.3

* Match the WordPress Abilities API nullable registration contract while preserving failure diagnostics and static-analysis compatibility.
* Refresh compatible admin starter lock entries for patched shell-quote 1.12.0 and source-map-js 1.2.2 without changing starter runtime package majors.
* Verify Syft publisher Sigstore bundles against the exact trusted release workflow and issuer; reject missing signatures and mismatched checksums before changing tool pins.
* Restore secure isolated WordPress Git tooling while retaining its Node 22-compatible environment. Adapt the two upstream imports only after exact source/version checks, with real clone/fetch/checkout and drift-rejection coverage.
* Align React, TypeScript and Python update policies with their supported runtimes. Refresh hash-locked Python tooling and qualify the pinned Semgrep scanner against all production permission rules and safe controls in required CI.

## v1.10.2

* Preserve pinned WordPress tooling alongside trusted release helpers in plugin, prerelease and foundation release workflows. Detached release drivers can now install their isolated WordPress environment after the original checkout is replaced or removed.
* Fail immediately when a trusted driver lacks its tooling directory or cannot copy its locked inputs, including calls made from shell conditionals.
* Qualify all seven workflow preservation commands with cold-install fixtures that verify the trusted package manifests and reject incomplete snapshots before copying files or running npm.

## v1.10.1

* Fix isolated Plugin Check startup for dependent plugins with `WORDPRESS_TEST_PLUGINS`, for example `woocommerce@11.1.2`. Explicitly pinned WordPress.org dependencies are installed before the child plugin and never included in its release ZIP. The configuration rejects URLs, floating versions, duplicate slugs and whitespace.
* Refresh WordPress environment tooling pins to `brace-expansion` 2.1.7 and `fast-uri` 3.1.8 to resolve denial-of-service and URI normalization advisories.
* Existing children without test dependencies keep the previous behavior. Children declaring `Requires Plugins` should configure exact dependency versions after adopting this verified foundation release.

## v1.10.0

* Add `AUTOMATION_PROFILE=local` conformance without foundation-owned hosted publishers, scheduled updates or deployment credentials, while preserving release eligibility checks. Managed automation remains the default; development readiness accepts matching experimental versions.
* Build clean checkouts from declared generated outputs and optional complete SHA-256 artifact manifests. Validate required source inputs and containment before building, clear only declared generated ownership, and reject missing, stale, excluded or changed outputs afterward.
* Serialize cooperating builds and retain independently verified package generations. Bind validation, SBOM, signing, attestation, upload and deployment to the captured generation; verify exact ZIP membership, bytes and modes, including admin UI lazy assets.
* Isolate implicit ZIP options, normalize directories to 0755 and files to 0644 or executable 0755, harden archive recovery, and preserve previous packages on ordinary failures. Document toolchain reproducibility and interrupted-operation limits.
* Provide complete verified exact-commit manual imports through the existing signed-release trust model, without automatic synchronization or publication. Autogenerated GitHub source archives remain incomplete exports.
* Support configurable downstream default branches with exact historical signing identities and trusted host API context. Foundation-source trust remains independently pinned to its protected main branch.
* Document and test adoption of an existing application-owned TypeScript/webpack/DataViews build with extracted WordPress dependencies, lazy chunks, CSS/RTL and licenses. Preserve application manifests and independently qualified WordPress minimums; the fixture’s WordPress 7.1 graph does not replace an existing application’s WordPress 6.9 qualification.

### Migration notes

* Core package verification, recovery and import tooling now require Python 3.10 or newer. Managed automation and the default `main` branch remain unchanged.
* Capture automation ownership before replacing a pre-receipt vendor tree. Published v1.8.3 and v1.9.0 migration paths are qualified; customized files require explicit reconciliation. Commit `.wp-plugin-base-automation.json` alongside the managed files. Unknown application workflows remain application-owned.
* A declared artifact manifest makes its parent directory disposable generated output. Keep source files outside it. Package directories use 0755, ordinary files 0644, and executable files 0755.
* Consumers that can overlap builds must use captured generation paths. Retain generations while consumers are active; ordinary rollback does not imply crash-durable recovery. Historical releases keep their original exact signing branch.

See the [local development](https://github.com/MatthiasReinholz/wp-plugin-base/blob/v1.10.0/docs/local-development.md), [package lifecycle](https://github.com/MatthiasReinholz/wp-plugin-base/blob/v1.10.0/docs/package-lifecycle.md), [manual import](https://github.com/MatthiasReinholz/wp-plugin-base/blob/v1.10.0/docs/manual-foundation-import.md), [downstream branches](https://github.com/MatthiasReinholz/wp-plugin-base/blob/v1.10.0/docs/downstream-branches.md) and [existing application adoption](https://github.com/MatthiasReinholz/wp-plugin-base/blob/v1.10.0/docs/existing-application-adoption.md) guides for configuration and adoption steps.

## v1.9.0

* Isolate generated runtime classes per plugin and validate REST/Abilities input consistently, including nullable values, normalized input, and permission configuration.
* Preserve published release bytes and provenance on retries; constrain authenticated source fetching, update branches, and dependency publication credentials. Keep authentication headers out of GitLab release notes and clean temporary credentials when header creation fails.
* Verify WordPress.org working-copy operations and compare exact package content before permitting release repair.
* Reject unsafe generation/build paths, symlink escapes, excluded runtime files, and incomplete foundation runtime packages.
* Centralize approved action pins, migrate reviewed child workflow references, stage migrated files, and clarify foundation versus child dependency ownership.
* Refresh development dependencies with compatible PHP 8.0 and Python 3.10 locks, coherent admin starters, and scoped overrides; guard admin saves and test real browser behavior.
* Preserve customized child files and PHPCS overlays; resolve complete managed manifests before mutations, retry interrupted output, and fail closed on listing or update-staging failures. Make generated agent guidance idempotent, isolate Git fixture environments, and clean only owned temporary WordPress environments.
* Harden tool installation, preserve file paths in Plugin Check diagnostics, keep security enforcement independent of SARIF reporting permissions, and require all independent validation, bootstrap, and runtime jobs to succeed; document migration and operational acceptance requirements.

## v1.8.3

* Validate the actual release branch and reject malformed release or hotfix branch names (#340)
* Remediate admin UI build-tool advisories and require Node.js 22.19 for the secured Lighthouse toolchain (#339)
* Refresh WordPress environment tooling dependencies and stabilize fixture cleanup (#339)
* Refresh admin UI security lockfiles (#338)
* ci: modernize plugin workflow foundations (#332)

## v1.8.2

* Preserve release formatting and update Markdown tooling (#327)
* Correct the release branch metadata used to finalize v1.8.2.

## v1.8.1

* Preserve child-project `parent_slug` settings when registering managed admin UI pages.

## v1.8.0

* Changed the managed foundation, child-project default, fixtures, and admin UI tooling contract from Node.js 20 to Node.js 22.
* Updated WordPress validation fixtures for WordPress 7.1 compatibility checks.
* Updated the managed PHP quality pack to security-fixed coding-standard dependencies.
* Stabilized changelog extraction fixtures by disabling asynchronous Git maintenance in temporary repositories.

## v1.7.15

* docs: record future enhancements
* docs: record future enhancements
* Harden tooling dependency and host audit policy (#181)
* chore(deps): bump github/codeql-action from 4.35.5 to 4.36.0 (#178)
* chore(deps-dev): bump tmp from 0.2.5 to 0.2.7 in /tools/wordpress-env (#180)
* chore(deps): bump yamllint in /tools/python-lint-tools (#179)

## v1.7.14

* Add admin UI header end marker (#176)

## v1.7.13

* Resolve remaining dependency alerts
* chore(deps): bump idna from 3.11 to 3.15 in /tools/python-semgrep (#173)
* chore(deps-dev): bump @wordpress/element (#166)
* chore(deps-dev): bump @wordpress/api-fetch (#165)
* chore(deps-dev): bump @wordpress/data (#161)
* chore(deps): bump semgrep in /tools/python-semgrep (#159)
* chore(deps-dev): bump @wordpress/i18n (#158)
* chore(deps-dev): bump @wordpress/env in /tools/wordpress-env (#157)
* chore(deps-dev): bump phpstan/phpstan (#156)
* chore(deps-dev): bump dealerdirect/phpcodesniffer-composer-installer (#152)
* chore(deps-dev): bump dealerdirect/phpcodesniffer-composer-installer (#150)
* chore(deps): bump urllib3 from 2.6.3 to 2.7.0 in /tools/python-semgrep (#149)
* chore(deps-dev): bump @babel/plugin-transform-modules-systemjs (#147)
* chore(deps-dev): bump fast-uri (#146)
* chore(deps-dev): bump fast-uri (#145)
* chore(deps-dev): bump fast-xml-builder in /tools/wordpress-env (#144)
* Harden release and workflow maintenance checks (#172)
* chore(deps-dev): bump axios (#143)
* chore(deps-dev): bump ip-address (#142)
* chore(deps): bump python-multipart in /tools/python-semgrep (#140)
* chore(deps-dev): bump axios (#139)
* chore(deps-dev): bump simple-git in /tools/wordpress-env (#137)
* chore(deps-dev): bump ip-address (#138)
* chore(deps-dev): bump phpstan/phpstan (#122)
* chore(deps-dev): bump @wordpress/env in /tools/wordpress-env (#124)
* chore(deps-dev): bump @wordpress/data (#126)
* chore(deps-dev): bump @wordpress/api-fetch (#127)
* chore(deps-dev): bump @wordpress/element (#129)
* chore(deps-dev): bump @wordpress/i18n (#133)
* chore(deps-dev): bump @wordpress/scripts (#134)
* chore(deps-dev): bump @wordpress/components (#135)

## v1.7.12

* Guard foundation changelog hygiene (#119)

## v1.7.11

* Harden child repository ergonomics (#117)

## v1.7.10

* Harden release verification and agent contracts
* Add prerelease tag publication for GitHub child plugins.
* Verify stable GitHub releases after publication and reject lightweight release tags in repair flows.
* Build deterministic ZIP archives for managed child packages.
* Harden release repair, runtime updater URL validation, REST endpoint scanning, and optional pack runtime behavior.
* Refresh Semgrep, ShellCheck, actionlint, Syft, and admin UI PostCSS pins.

## v1.7.9

* Harden release readiness validation (#113)
* chore(deps-dev): bump fast-xml-parser in /tools/wordpress-env (#112)
* Tighten PR-body changelog extraction semantics and coverage
* Add PR/MR body section extraction for changelog notes
* docs(sync): harden PHPUnit bootstrap-child migration guidance (#110)

## v1.7.8

* chore(ci): enforce local pre-push validation and bump setup-node pin (#108)
* chore(deps): bump semgrep in /tools/python-semgrep (#107)

## v1.7.7

* Fix docs guard regression test distignore rewrite (#104)
* Preserve configured README_FILE when docs path is excluded (#103)
* Enforce runtime-clean packaging by excluding docs content (#102)
* Clarify PHPUnit bridge contract and sync strict matrix managed files (#101)

## v1.7.6

* Remediate admin-ui template dependency vulnerabilities
* Fix foundation provenance compare direction on GitHub
* Bootstrap release security tools before foundation provenance verify (#97)

## v1.7.5

* Fix finalize workflows merge-commit fetch in shallow clones (#95)
* Foundation release v1.7.4 (#94)
* Harden workflow permissions and patch markdownlint transitive advisory (#93)

## v1.7.4

* Harden workflow permissions and patch markdownlint transitive advisory (#93)

## v1.7.3

* Prune disabled pack trees from REST contract scan
* Prune disabled pack trees from lint traversal

## v1.7.2

* Clarify host-specific release repair documentation

## v1.7.1

* chore(deps-dev): bump phpstan/phpstan (#85)
* Close dependency backlog and refresh reviewed CodeQL pin (#84)
* chore(deps): bump python-multipart in /tools/python-semgrep (#61)
* chore(deps-dev): bump phpstan/phpstan (#65)
* Clarify downstream release and runtime updater contracts

## v1.7.0

* Fix remaining auth fixture wrapper handling
* Restore GitHub workflow token remediation guidance
* Fix auth fixture git wrapper argument matching
* Normalize GitHub HTTPS auth before fetch and push (#80)
* Sync child env example foundation version with VERSION (#79)
* Run runtime-pack and admin UI policy tests in foundation checks (#78)
* Declare optional GitLab secret in reusable update workflow (#77)
* Align workflow auth contracts with foundation policy checks (#76)
* Disable checkout credential persistence in update workflows (#75)
* Restore complete schema defaults after config-schema regression (#74)
* Align schema defaults for REST and admin UI config (#73)
* Align schema API base defaults with config loader (#72)
* Fix foundation CI blockers before v1.7.0 release (#71)
* Fix GitHub release-branch push auth in change request helper (#70)
* Add single-host multi-platform GitHub/GitLab support contract (#69)
* fix: load quality-pack child hooks after WP test helpers (#67)
* feat: add quality pack overlays and PHPUnit bridge (#66)
* chore: tighten foundation contracts and runtime tooling (#62)

## v1.6.3

* Fix child prepare-release credential persistence

## v1.6.2

* Fix PR auth header reuse in release workflows
* Keep child workflow artifact pins in sync
* Allow upload-artifact v7.0.1 pin in workflow policy
* Polish runtime follow-up consistency and admin UI resilience
* Tighten validation helper naming consistency
* Harden runtime pack review follow-ups
* chore(deps): bump semgrep in /tools/python-semgrep
* chore(deps-dev): bump phpstan/phpstan
* chore(deps): bump actions/upload-artifact from 7.0.0 to 7.0.1

## v1.6.1

* Apply local workspace updates across updater automation, validation, and runtime packs

## v1.6.0

* Fix runtime pack negative fixture setup
* Ignore seeded node_modules in forbidden-file scan
* Fix runtime pack fixture marker syntax
* Normalize shell script indentation
* Fix REST contract scanner shellcheck warning
* Harden runtime pack permission callbacks
* Add REST operations and admin UI runtime packs

## v1.5.1

* feat: standardize external dependency updater and docs (#42)

## v1.5.0

* Exclude vendored updater runtime from editorconfig checks
* Expand codespell ignore for vendored updater typo
* Allow upstream misspelling in vendored updater parser
* Exclude vendored updater runtime from codespell
* Configure markdownlint ignores for vendored updater docs
* Ignore vendored updater markdown in foundation lint
* Exclude vendored updater docs from markdown lint
* Fix updater template substitution shellcheck warnings
* Add multi-channel distribution with WooCommerce and GitHub updater
* fix(ci): address ShellCheck SC2155 in release notes generator

## v1.4.0

* feat: add release quality and automation enhancements
* harden foundation release version contract automation (#37)
* fix: align child env foundation pin with v1.3.1 release (#36)

## v1.3.1

* chore(deps): bump semgrep in /tools/python-semgrep (#31)
* fix distignore negative fixture in validate-full (#34)
* fix ci regressions in markdown and plugin-check timeout (#33)
* harden release and api reliability controls (#32)
* harden foundation validation and update controls (#29)
* standardize external dependency trust notices
* automate plugin-check updates with age gate
* make plugin-check updater manual-only
* harden composer-backed validation retries
* chore: checkpoint outstanding local changes
* harden config validation and update safety
* fix: harden workflow audit and release trust paths (#23)
* ci(audit): allow updated github/codeql-action upload-sarif pin
* chore(deps-dev): bump @wordpress/env in /tools/wordpress-env
* chore(deps): bump github/codeql-action from 4.34.1 to 4.35.1

## v1.3.0

* Strengthen WordPress plugin security validation with Semgrep SARIF reporting, high-signal authorization pattern checks, and justified suppression workflow.
* Introduce a minimal, focused security pack and reduce toolchain/lockfile bloat for faster, clearer security checks.
* Add strict Sigstore consumer verification tooling and tighten release identity verification contracts.
* Enforce deployment-environment reviewer protection in strict CI/release readiness mode.
* Add SBOM and release-signing smoke validation in foundation CI.
* Extend workflow URL-host audit policy with controlled `EXTRA_ALLOWED_HOSTS` overrides.
* Remove mutable WooCommerce QIT CLI version input to improve reproducibility.
* Improve packaging hygiene for child templates and managed security artifacts.
* Add coding-agent-first secure plugin coding contract documentation for Codex/Claude style workflows.
* Improve CI tooling robustness (Python tool isolation, safer lint/install handling, and readiness regression coverage).

## v1.2.3

* Harden workflow and release infrastructure with stricter action pinning, tighter workflow audit coverage, and stronger foundation update provenance verification.
* Add WordPress readiness validation, Plugin Check integration, and an opt-in PHP quality pack for child plugin repositories.
* Make the foundation more portable by relaxing the `rg` requirement in validation paths and carrying the `tools/wordpress-env/.npmrc` policy with temporary installs.

## v1.2.2

* Update generated project workflow pins for actions/checkout and shivammathur/setup-php.
* Document exactly how to enable GitHub Actions pull request creation in repository and organization settings.
* Switch the foundation repository license text to GPL v3 and align fixture license markers.

## v1.2.1

* Fix first-release note generation when no prior semver tags exist.

## v1.2.0

* change PR automation handling
* change handling when tag/branch already exist
* chore(deps): bump actions/checkout from 5.0.1 to 6.0.2
* chore(deps): bump shivammathur/setup-php
* enhance workflow access and documentation

## v1.1.3

* Tighten release ordering and messaging

## v1.1.2

* Publish releases in finalize workflows

## v1.1.1

* Grant release workflows pull-request read access so release PR validation works in private repositories.

## v1.1.0

* Switch project workflows to local managed files

## v1.0.2

* update documentation to clarify usage

## v1.0.1

* Add staged foundation release flow and docs

## v1.0.0

* Initial generic WordPress plugin foundation release.
