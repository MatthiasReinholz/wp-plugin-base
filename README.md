# wp-plugin-base

`wp-plugin-base` is a GitHub-centric foundation for WordPress plugin repositories.

It provides two reuse layers:

- reusable GitHub Actions workflows for CI, release preparation, tagging, publishing, and foundation updates
- vendored source under `.wp-plugin-base/` inside child repos for scripts, templates, and documentation

The foundation is a development dependency only. It must never be a runtime dependency of the released plugin ZIP.

## Child Repo Contract

Each child repo should contain:

- `.wp-plugin-base/` populated from this repo via `git subtree`
- `.wp-plugin-base.env` with repo-specific metadata
- plugin-local code and assets
- thin workflow wrappers in `.github/workflows/`

Managed files are generated from `templates/child/` by running:

```bash
bash .wp-plugin-base/scripts/update/sync_child_repo.sh
```

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

## WordPress.org Deploy

WordPress.org deploy is built into the shared release workflow and is disabled by default.

To enable it in a child repo:

1. set the repository or environment variable `WP_ORG_DEPLOY_ENABLED=true`
2. set `WORDPRESS_ORG_SLUG` in `.wp-plugin-base.env`
3. provide `SVN_USERNAME` and `SVN_PASSWORD` as GitHub secrets

If `WP_ORG_DEPLOY_ENABLED` is unset or any value other than `true`, the release workflow skips SVN deploy.
