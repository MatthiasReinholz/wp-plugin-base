# wp-plugin-base

`wp-plugin-base` is a GitHub-centric foundation for WordPress plugin repositories.

It is the **delivery and governance layer** for plugin repos:

- managed local GitHub Actions workflows
- release, packaging, and optional WordPress.org deployment automation
- workflow hardening and provenance checks
- vendored scripts, templates, and documentation under `.wp-plugin-base/`

It is **not** a plugin runtime framework. It does not currently provide plugin-side DI, PSR-4 runtime scaffolding, settings abstractions, REST controllers, or block architecture. Those concerns should remain outside this repo or move into a future companion runtime layer.

It provides two reuse layers:

- managed workflow files generated into your project's `.github/workflows/`
- a managed `.github/dependabot.yml` file for GitHub Actions dependency updates
- vendored source under `.wp-plugin-base/` inside your project for scripts, templates, and documentation

The foundation is a development dependency only. It must never be a runtime dependency of the released plugin ZIP.

The repository also enforces a tracked-file hygiene policy. Files such as `.DS_Store`, `Thumbs.db`, `Desktop.ini`, editor workspace folders, and transient debug logs are treated as forbidden repository content and fail validation if present.

## Who It Is For

`wp-plugin-base` is optimized first for product teams and maintainers who need:

- repeatable release automation across plugin repositories
- a hardened GitHub Actions policy by default
- a vendored, reviewable infrastructure layer instead of opaque reusable workflows
- a clear update path for shared repo automation

If you only need a minimal plugin starter and do not want shared CI/release governance, `wp scaffold plugin` or a simpler starter is a better fit.

## Quick Start

1. Vendor this repo into your plugin repository at `.wp-plugin-base/`.
2. Create `.wp-plugin-base.env` from `.wp-plugin-base/templates/child/.wp-plugin-base.env.example`.
3. Run `bash .wp-plugin-base/scripts/update/sync_child_repo.sh`.
4. Run `bash .wp-plugin-base/scripts/ci/validate_project.sh`.
5. Commit `.wp-plugin-base/`, `.wp-plugin-base.env`, and the generated managed files.

For the foundation repo itself, run:

```bash
bash scripts/foundation/validate.sh
bash scripts/foundation/validate-full.sh
```

`validate.sh` is the fast local suite. `validate-full.sh` requires Docker and also runs the WordPress readiness and Plugin Check fixtures.

## Local Tooling Contract

Fast local validation depends on these commands being available:

- `bash`
- `git`
- `php`
- `node`
- `ruby`
- `perl`
- `jq`
- `rsync`
- `zip`
- `unzip`

`rg` is optional. The workflow auditor uses it when available and falls back to `grep` otherwise.

Full local validation and optional flows need additional tools:

- `gh` for GitHub release and pull request automation
- `docker` for WordPress readiness validation, Plugin Check, and the full foundation validation suite
- `python3` for WordPress.org deployment credential handling
- `svn` for WordPress.org deployment
- `wp` is not required locally; release-time POT generation uses the pinned `@wordpress/env` bundle when `POT_FILE` is configured

The shared scripts now fail fast with explicit missing-tool errors instead of failing deeper into release or update flows.

Foundation-only linting uses `shellcheck`, `actionlint`, `yamllint`, `markdownlint-cli2`, `codespell`, `editorconfig-checker`, and `gitleaks` when they are installed locally. Foundation CI installs and runs them strictly even if they are absent on a contributor machine.

On macOS, install the binary tools locally with:

```bash
brew install shellcheck actionlint editorconfig-checker gitleaks
```

Install Markdown linting separately with:

```bash
npm install -g markdownlint-cli2
```

`tools/wordpress-env` is a separate lockfile-backed npm tooling bundle. Shared scripts install it with `npm ci --no-audit --no-fund` from the committed `package-lock.json`, and the local `.npmrc` now travels with that temp install so the Node engine policy stays explicit.

## Security Model

`wp-plugin-base` assumes a locked-down GitHub Actions posture:

- workflows are local to your project and run against the checked-out repository
- every external action must be pinned to a full commit SHA
- only a small approved action allowlist is permitted
- release and update workflows use repo-local shell scripts where practical instead of additional third-party actions
- foundation self-updates only trust published foundation releases that pass provenance checks

See [Security model](docs/security-model.md) for the full policy and the current approved action set.

## Access Requirements

For your project to consume this foundation successfully:

- your project must commit both `.wp-plugin-base/` and `.wp-plugin-base.env` before the shared workflows can run
- if you use the automated foundation self-update workflow, the GitHub Actions runner must be able to read releases from `FOUNDATION_REPOSITORY`
- if you want workflows such as `prepare-release` or `update-foundation` to open pull requests, the repository must allow GitHub Actions to create and approve pull requests

If those conditions are not met, the local project workflows will either fail to find `.wp-plugin-base/` or, for self-update only, fail to reach the foundation release source.

To enable pull request creation in GitHub:

1. Open your repository on GitHub.
2. Go to `Settings` -> `Actions` -> `General`.
3. Scroll to `Workflow permissions`.
4. Select `Read and write permissions`.
5. Enable `Allow GitHub Actions to create and approve pull requests`.
6. Save the changes.

If `Allow GitHub Actions to create and approve pull requests` is greyed out:

1. Open the parent organization on GitHub.
2. Go to `Settings` -> `Actions` -> `General`.
3. Allow repositories in the organization to let GitHub Actions create and approve pull requests.
4. Return to the repository and enable the repository-level setting there if GitHub still requires it.

See [Troubleshooting](docs/troubleshooting.md) for the failure modes and the organization-level case.

## Project Contract

Each project repository should contain:

- `.wp-plugin-base/` populated from this repo as vendored source
- `.wp-plugin-base.env` with project-specific metadata
- plugin-local code and assets
- managed local workflow files in `.github/workflows/`

Managed files are generated from `templates/child/` by running:

```bash
bash .wp-plugin-base/scripts/update/sync_child_repo.sh
```

Validate the repo contract locally with:

```bash
bash .wp-plugin-base/scripts/ci/validate_project.sh
```

You can bootstrap `.wp-plugin-base/` with `git subtree` if you want that history locally, but the shared update workflow only requires a normal vendored copy.

The managed `.github/dependabot.yml` file checks for GitHub Actions updates every week. Projects should keep Dependabot enabled so pinned action SHAs keep moving forward through normal review PRs.

Managed child CI also runs a separate `gitleaks` secret-scan job by default. That job installs only the pinned scanner binary, scans the project checkout, and fails the workflow if secrets are detected.

Release publishing now emits three independent trust artifacts:

- GitHub build attestation for the released package
- CycloneDX SBOM for the packaged release contents
- Sigstore keyless bundle for the released blob

Use `bash .wp-plugin-base/scripts/release/verify_sigstore_bundle.sh <owner/repo> <artifact-path> <bundle-path> plugin` for strict consumer verification against the expected release workflows.

The foundation repository also runs an OpenSSF `scorecard` workflow on the default branch and publishes SARIF findings to GitHub code scanning.
It also includes a scheduled `update-plugin-check` workflow that proposes PRs for compatible new `WordPress/plugin-check` releases.

## Recommended GitHub Actions Policy

Apply this policy in GitHub under `Settings` -> `Actions` -> `General` for each project repository or, preferably, at the organization level:

1. Under `Actions permissions`, choose `Allow OWNER, and select non-OWNER, actions and reusable workflows`.
2. Allow GitHub-authored actions.
3. Allow only the specific non-GitHub actions that the current foundation version documents in [Security model](docs/security-model.md).
4. Enable `Require actions to be pinned to a full-length commit SHA`.

This foundation already generates workflows that match that policy. Keeping the GitHub setting aligned means GitHub rejects unexpected workflow drift before a compromised action can run.

## Foundation Release Contract

Foundation releases use semver tags with a `v` prefix such as `v1.0.1`.

- your project pins `FOUNDATION_VERSION` to one exact foundation release
- automated foundation update PRs only consider published GitHub Releases, not arbitrary tags or branch heads
- automatic updates stay within the current major series
- major foundation upgrades are manual

## Config

Required keys in `.wp-plugin-base.env`:

- `FOUNDATION_REPOSITORY`
- `FOUNDATION_VERSION`
- `PLUGIN_NAME`
- `PLUGIN_SLUG`
- `MAIN_PLUGIN_FILE`
- `README_FILE`
- `ZIP_FILE`
- `PHP_VERSION`
- `NODE_VERSION`

Optional keys:

- `PHP_RUNTIME_MATRIX`
- `VERSION_CONSTANT_NAME`
- `POT_FILE`
- `POT_PROJECT_NAME`
- `WORDPRESS_ORG_SLUG`
- `WORDPRESS_READINESS_ENABLED`
- `WORDPRESS_QUALITY_PACK_ENABLED`
- `WORDPRESS_SECURITY_PACK_ENABLED`
- `WOOCOMMERCE_QIT_ENABLED`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY`
- `EXTRA_ALLOWED_HOSTS`
- `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE`
- `PACKAGE_INCLUDE`
- `PACKAGE_EXCLUDE`
- `CHANGELOG_HEADING`
- `PRODUCTION_ENVIRONMENT`
- `CODEOWNERS_REVIEWERS`

Use shell-safe `KEY=value` syntax. Quote values that contain spaces, for example `PLUGIN_NAME="Example Plugin"`. `ZIP_FILE` must be a simple `.zip` filename, not a path.

`.wp-plugin-base.env` is a file committed in your project repository. It is not a GitHub Actions variable.

Set `CODEOWNERS_REVIEWERS` only if you want the generated project files to include a `.github/CODEOWNERS` file. Use one or more GitHub handles or teams separated by spaces, for example `CODEOWNERS_REVIEWERS="@your-org/platform @your-user"`.

`WORDPRESS_QUALITY_PACK_ENABLED=true` enables the broader PHP quality pack with PHPCS, PHPStan, PHPUnit, and Composer audit checks.

`WORDPRESS_SECURITY_PACK_ENABLED=true` enables a narrower security-focused pack during WordPress readiness validation. That pack runs explicit `WordPress.Security`, `WordPress.DB`, and `WordPress.WP.Capabilities` sniffs, blocks risky public endpoint patterns, and audits root Composer/npm runtime dependencies when lock files are present.

Use `.wp-plugin-base-security-suppressions.json` (or set `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE`) to declare intentional public endpoint exceptions with mandatory justification.

`WP_PLUGIN_BASE_PLUGIN_CHECK_*` keys provide optional policy controls for Plugin Check execution during WordPress readiness validation:

- `..._CHECKS` runs only specific checks.
- `..._EXCLUDE_CHECKS` excludes specific checks.
- `..._CATEGORIES` filters checks by categories such as `plugin_repo,security`.
- `..._IGNORE_CODES` ignores specific Plugin Check result codes.
- `..._STRICT_WARNINGS=true` fails readiness validation on warnings in addition to errors.
- `..._SEVERITY`, `..._ERROR_SEVERITY`, and `..._WARNING_SEVERITY` pass through severity thresholds to Plugin Check.

`PHP_RUNTIME_MATRIX` enables an additional CI smoke job across the listed interpreter versions, for example `PHP_RUNTIME_MATRIX=8.1,8.2,8.3`. The matrix reruns repository validation and WordPress metadata checks with each configured PHP version. Set `PHP_RUNTIME_MATRIX_MODE=strict` to also run PHPUnit in the matrix when `phpunit.xml.dist` and the managed quality-pack tool bundle are present.

`WOOCOMMERCE_QIT_ENABLED=true` syncs an optional manual WooCommerce QIT workflow into the child repository. That workflow is intended for WooCommerce Marketplace/partner use, expects `QIT_USER` and `QIT_APP_PASSWORD` secrets plus a manually provided WooCommerce extension slug, and uses a pinned internal `woocommerce/qit-cli` version.

`EXTRA_ALLOWED_HOSTS` allows additional outbound URL hosts for workflow/script audit policy (comma-separated hostnames only). Keep this list minimal.

## WordPress.org Deploy

WordPress.org deploy is built into the shared release workflow and is disabled by default.

To enable it in your project:

1. set `WP_ORG_DEPLOY_ENABLED=true` as either:
   - a GitHub Actions repository variable in the repository settings, or
   - a GitHub Actions environment variable on the selected deployment environment
2. set `WORDPRESS_ORG_SLUG` in `.wp-plugin-base.env`
3. provide `SVN_USERNAME` and `SVN_PASSWORD` as GitHub Actions secrets on the protected deployment environment when possible

If `WP_ORG_DEPLOY_ENABLED` is unset or any value other than `true`, the release workflow skips SVN deploy.

For stronger review on production publishing, protect the deployment environment named by `PRODUCTION_ENVIRONMENT` and require at least one reviewer before the workflow can access deploy credentials. CI and release readiness checks now fail when WordPress.org deploy is enabled and reviewer protection cannot be verified.

## Guides

- [New project setup](docs/new-project.md)
- [Existing project migration](docs/existing-project-migration.md)
- [Product layers](docs/layers.md)
- [Security model](docs/security-model.md)
- [Secure plugin coding contract](docs/secure-plugin-coding-contract.md)
- [Compatibility and public contract](docs/compatibility.md)
- [Foundation release process](docs/foundation-release-process.md)
- [Changelog policy](docs/changelog-policy.md)
- [Update model](docs/update-model.md)
- [Troubleshooting](docs/troubleshooting.md)
