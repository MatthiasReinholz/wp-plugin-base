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

`finalize-release.yml` is the normal automated publish path. `release.yml` is the manual recovery workflow for an already existing tag. `.github/dependabot.yml` opens reviewable PRs for GitHub Actions version updates.

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

If WordPress.org deploy is enabled, keep `SVN_USERNAME` and `SVN_PASSWORD` in GitHub Actions environment secrets when possible, and protect the `PRODUCTION_ENVIRONMENT` environment with at least one reviewer.

## Security Expectations

This project inherits the foundation security model:

- workflow action references must stay pinned to full commit SHAs
- the project should keep GitHub Actions limited to the approved action allowlist for the pinned foundation version
- workflow, script, and dependency-policy changes should be reviewed like privileged infrastructure changes
- `update-foundation` only trusts published foundation releases that pass provenance checks
