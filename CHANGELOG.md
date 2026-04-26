# Changelog

## Unreleased

* Add prerelease tag publication for GitHub child plugins.
* Verify stable GitHub releases after publication and reject lightweight release tags in repair flows.
* Build deterministic ZIP archives for managed child packages.

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
