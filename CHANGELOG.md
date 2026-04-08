# Changelog

## Unreleased

* Make Semgrep SARIF upload reliable by splitting scan/upload/fail phases in CI and preserving SARIF even when findings occur.
* Minimize the security pack toolchain and lockfile footprint to keep security validation focused and lightweight.
* Add strict Sigstore bundle verification tooling and documentation for consumers, and tighten verifier identity matching.
* Enforce strict deployment environment reviewer checks in CI/release readiness paths.
* Introduce justified suppression flow for intentional public endpoints and tighten authorization-pattern scanning semantics.
* Add configurable workflow URL host allowlist extensions via `EXTRA_ALLOWED_HOSTS` while keeping strict defaults.
* Remove mutable WooCommerce QIT CLI version input to preserve reproducibility and pinned dependency behavior.
* Improve packaging hygiene for child templates (`export-ignore` and dist exclusions for security-pack internals).
* Add coding-agent-first secure plugin coding contract guidance for Codex/Claude style agent workflows.

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
