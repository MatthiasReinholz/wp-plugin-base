# Contributing

This file is managed by `wp-plugin-base`. Update it from the foundation repo instead of hand-editing it here.

## Branching Model

This repository uses short-lived branches:

- `main`: protected and intended to stay releasable
- `feature/<topic>`: normal development work
- `release/<version>`: release preparation only
- `hotfix/<version>`: urgent production fixes branched from `main`

Do not push directly to `main`. Open a pull request instead.

## Release Process

Releases are merge-driven and tag-backed. A branch push must never publish a plugin release.

Normal release flow:

1. Merge the intended feature branches into `main`.
2. Run the `prepare-release` workflow and choose `patch`, `minor`, `major`, or `custom`.
   Rerunning `prepare-release` for the same version refreshes the existing `release/x.y.z` branch and updates the existing PR if needed.
3. Review the generated `release/x.y.z` pull request.
4. Review the auto-generated changelog entry, adjust it if needed, and complete any plugin-specific smoke tests.
5. Merge the `release/x.y.z` pull request into `main`.
6. The merged release PR automatically creates the `x.y.z` tag and publishes the GitHub release in the same workflow.
7. Use `release.yml` only as a manual recovery path for an existing tag if automatic publication needs to be repeated.

Hotfixes use the same model from `hotfix/x.y.z` branches.

## CI And Release Automation

This project uses local managed workflow files generated from `wp-plugin-base` version `__FOUNDATION_VERSION__`.

Managed workflow files:

- `.github/dependabot.yml`
- `.github/CODEOWNERS` when `CODEOWNERS_REVIEWERS` is set in `.wp-plugin-base.env`
- `.github/workflows/ci.yml`
- `.github/workflows/prepare-release.yml`
- `.github/workflows/finalize-release.yml`
- `.github/workflows/release.yml`
- `.github/workflows/update-foundation.yml`
- `.editorconfig`
- `.gitattributes`
- `.gitignore`
- `.distignore`
- `SECURITY.md`
- `uninstall.php.example`
- `.phpcs.xml.dist`, `phpstan.neon.dist`, `phpunit.xml.dist`, `tests/bootstrap.php`, `tests/wp-plugin-base/PluginLoadsTest.php`, and `.wp-plugin-base-quality-pack/**` when `WORDPRESS_QUALITY_PACK_ENABLED=true`
- `.phpcs-security.xml.dist` and `.wp-plugin-base-security-pack/**` when `WORDPRESS_SECURITY_PACK_ENABLED=true`
- `.github/workflows/woocommerce-qit.yml` when `WOOCOMMERCE_QIT_ENABLED=true`
- `.wp-plugin-base-security-suppressions.json`, or the path configured by `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE`, when absent

`finalize-release.yml` is the normal automated publish path. `release.yml` is the manual recovery workflow for an already existing tag. `.github/dependabot.yml` opens reviewable PRs for GitHub Actions version updates.
Managed CI also runs a separate `gitleaks` secret-scan job by default.
When `WORDPRESS_QUALITY_PACK_ENABLED=true` or `WORDPRESS_SECURITY_PACK_ENABLED=true`, treat those settings as readiness submodes. Both require `WORDPRESS_READINESS_ENABLED=true`.

When `WORDPRESS_SECURITY_PACK_ENABLED=true`, readiness validation also runs a focused WordPress security pack:

- explicit `WordPress.Security` sniffs for escaping, nonce verification, and sanitized input
- explicit `WordPress.DB` sniffs for direct queries and prepared SQL
- explicit `WordPress.WP.Capabilities` checks
- a narrow REST authorization pattern scan that fails on `permission_callback => __return_true`
- dependency audits for root `composer.lock` and runtime `package-lock.json` files when present

If `PHP_RUNTIME_MATRIX` is set, CI also runs a lightweight runtime smoke job across the listed PHP versions. That job reruns repository validation and WordPress metadata checks with each interpreter version so syntax- and interpreter-level issues surface before release. Set `PHP_RUNTIME_MATRIX_MODE=strict` to additionally run PHPUnit in the matrix when `phpunit.xml.dist` and the managed quality-pack tool bundle are present.

If `WOOCOMMERCE_QIT_ENABLED=true`, sync also manages a manual `woocommerce-qit` workflow. That workflow is intentionally opt-in, expects WooCommerce QIT access plus `QIT_USER` and `QIT_APP_PASSWORD` secrets, and defaults to the pinned `woocommerce/qit-cli` version declared by the workflow input.

If this repository does not already have a `CHANGELOG.md`, the first sync also seeds one from the foundation template. After that initial creation, the project owns its changelog content.

Before opening or merging changes, run:

```bash
bash .wp-plugin-base/scripts/ci/validate_project.sh
```

That command enforces the generated managed-file surface, not just `.github/workflows/*`. Managed workflow files also need to use the `.yml` extension; `.yaml` workflow files are rejected by project and foundation validation.

`prepare-release.yml` and `update-foundation.yml` need the GitHub repository setting `Allow GitHub Actions to create and approve pull requests`.

Enable it in GitHub under `Settings` -> `Actions` -> `General`:

1. Under `Actions permissions`, choose `Allow OWNER, and select non-OWNER, actions and reusable workflows`.
2. Allow GitHub-authored actions and only the specific non-GitHub actions documented by the foundation version vendored in this repository.
3. Enable `Require actions to be pinned to a full-length commit SHA`.
4. Set `Workflow permissions` to `Read and write permissions`.
5. Enable `Allow GitHub Actions to create and approve pull requests`.
6. Save the change.

If that option is greyed out, an organization owner must allow it first in the organization under `Settings` -> `Actions` -> `General`.

The WordPress.org deploy path is built in but opt-in. It only runs when `WP_ORG_DEPLOY_ENABLED=true`.

Set `WP_ORG_DEPLOY_ENABLED` in GitHub Actions settings as either:

- a repository variable for the whole repository, or
- an environment variable on the deployment environment used by the release workflow

If WordPress.org deploy is enabled, keep `SVN_USERNAME` and `SVN_PASSWORD` in GitHub Actions environment secrets when possible, and protect the `PRODUCTION_ENVIRONMENT` environment with at least one reviewer. Readiness validation warns locally when that environment cannot be verified yet, and the generated GitHub Actions workflows fail strictly when deploy protection cannot be verified in CI.

## Security Expectations

This project inherits the foundation security model:

- workflow action references must stay pinned to full commit SHAs
- the project should keep GitHub Actions limited to the approved action allowlist for the pinned foundation version
- workflow, script, and dependency-policy changes should be reviewed like privileged infrastructure changes
- `update-foundation` only trusts published foundation releases that pass provenance checks
