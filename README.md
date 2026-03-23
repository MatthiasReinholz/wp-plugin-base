# wp-plugin-base

`wp-plugin-base` is a GitHub-centric foundation for WordPress plugin repositories.

It provides two reuse layers:

- managed workflow files generated into your project's `.github/workflows/`
- a managed `.github/dependabot.yml` file for GitHub Actions dependency updates
- vendored source under `.wp-plugin-base/` inside your project for scripts, templates, and documentation

The foundation is a development dependency only. It must never be a runtime dependency of the released plugin ZIP.

## Access Requirements

For your project to consume this foundation successfully:

- your project must commit both `.wp-plugin-base/` and `.wp-plugin-base.env` before the shared workflows can run
- if you use the automated foundation self-update workflow, the GitHub Actions runner must be able to read releases from `FOUNDATION_REPOSITORY`
- if you want workflows such as `prepare-release` or `update-foundation` to open pull requests, the repository must allow GitHub Actions to create and approve pull requests

If those conditions are not met, the local project workflows will either fail to find `.wp-plugin-base/` or, for self-update only, fail to reach the foundation release source.

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

You can bootstrap `.wp-plugin-base/` with `git subtree` if you want that history locally, but the shared update workflow only requires a normal vendored copy.

The managed `.github/dependabot.yml` file checks for GitHub Actions updates every week. Projects should keep Dependabot enabled so pinned action SHAs keep moving forward through normal review PRs.

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

- `VERSION_CONSTANT_NAME`
- `POT_FILE`
- `POT_PROJECT_NAME`
- `WORDPRESS_ORG_SLUG`
- `PACKAGE_INCLUDE`
- `PACKAGE_EXCLUDE`
- `CHANGELOG_HEADING`
- `PRODUCTION_ENVIRONMENT`

Use shell-safe `KEY=value` syntax. Quote values that contain spaces, for example `PLUGIN_NAME="Example Plugin"`.

`.wp-plugin-base.env` is a file committed in your project repository. It is not a GitHub Actions variable.

## WordPress.org Deploy

WordPress.org deploy is built into the shared release workflow and is disabled by default.

To enable it in your project:

1. set `WP_ORG_DEPLOY_ENABLED=true` as either:
   - a GitHub Actions repository variable in the repository settings, or
   - a GitHub Actions environment variable on the selected deployment environment
2. set `WORDPRESS_ORG_SLUG` in `.wp-plugin-base.env`
3. provide `SVN_USERNAME` and `SVN_PASSWORD` as GitHub Actions secrets

If `WP_ORG_DEPLOY_ENABLED` is unset or any value other than `true`, the release workflow skips SVN deploy.

## Guides

- [New project setup](docs/new-project.md)
- [Existing project migration](docs/existing-project-migration.md)
- [Foundation release process](docs/foundation-release-process.md)
- [Update model](docs/update-model.md)
- [Troubleshooting](docs/troubleshooting.md)
