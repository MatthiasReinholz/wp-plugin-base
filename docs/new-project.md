# New Project Setup

Use this path when you are starting a new WordPress plugin repo from scratch.

## Steps

1. Create the plugin repository and protect `main`.
2. Copy or subtree-add `wp-plugin-base` into `.wp-plugin-base/`.
3. Create `.wp-plugin-base.env` from `.wp-plugin-base/templates/child/.wp-plugin-base.env.example`.
4. Fill in the required values:
   - `FOUNDATION_REPOSITORY`
   - `FOUNDATION_VERSION`
   - `PLUGIN_NAME`
   - `PLUGIN_SLUG`
   - `MAIN_PLUGIN_FILE`
   - `README_FILE`
   - `ZIP_FILE`
   - `PHP_VERSION`
   - `NODE_VERSION`
5. Set optional values only if the repo layout differs from the defaults.
6. Run `bash .wp-plugin-base/scripts/update/sync_child_repo.sh`.
7. Commit the vendored foundation, config, and generated managed files, including `.github/dependabot.yml`.
8. Add GitHub Actions settings:
   - `SVN_USERNAME` as a GitHub Actions secret
   - `SVN_PASSWORD` as a GitHub Actions secret
   - `WP_ORG_DEPLOY_ENABLED=true` only if WordPress.org deploy should be enabled, as either a GitHub Actions repository variable or a GitHub Actions environment variable
9. In GitHub, open `Settings` -> `Actions` -> `General`.
10. Under `Workflow permissions`, select `Read and write permissions`.
11. Enable `Allow GitHub Actions to create and approve pull requests` so `prepare-release` and `update-foundation` can open PRs.
12. If that option is greyed out, ask an organization owner to enable it in the organization under `Settings` -> `Actions` -> `General` first.
13. If you plan to use the automated foundation self-update workflow, confirm that GitHub Actions in your project can access releases from `FOUNDATION_REPOSITORY`.
14. Leave Dependabot enabled so weekly GitHub Actions update PRs can keep the pinned action SHAs current.

## Default Layout Assumptions

The simplest setup assumes:

- the main plugin file is at repo root
- `readme.txt` is at repo root
- the plugin version is stored in the plugin header and `readme.txt`
- changelog sections use `= x.y.z =`
- packaging can start from repo root and exclude development files via `.distignore`

If your repo matches those assumptions, the only optional value most projects need is `WORDPRESS_ORG_SLUG`.
