# New Project Setup

Use this path when you are starting a new WordPress plugin repo from scratch.
If you already have a plugin repository, use [Existing Project Migration](existing-project-migration.md) instead.

## Steps

1. Create the plugin repository and protect `main`.
2. Copy or subtree-add `wp-plugin-base` into `.wp-plugin-base/`.
3. Create the plugin main file and `readme.txt` if they do not already exist.
4. Create `.wp-plugin-base.env` from `.wp-plugin-base/templates/child/.wp-plugin-base.env.example`.
5. Fill in the required values:
   - `FOUNDATION_REPOSITORY`
   - `FOUNDATION_VERSION`
   - `PLUGIN_NAME`
   - `PLUGIN_SLUG`
   - `MAIN_PLUGIN_FILE`
   - `README_FILE`
   - `ZIP_FILE`
   - `PHP_VERSION`
   - `NODE_VERSION`
6. Set optional values only if the repo layout differs from the defaults.
   Keep `ZIP_FILE` as a simple filename such as `example-plugin.zip`, not a path.
   If your install ZIP needs files from `packages/` or `routes/`, add them explicitly through `PACKAGE_INCLUDE` and remove only the repo-relative paths that must stay out of the package through `PACKAGE_EXCLUDE`.
   Keep `PACKAGE_INCLUDE`, `PACKAGE_EXCLUDE`, and `DISTIGNORE_FILE` repo-relative. `DISTIGNORE_FILE` must point to a `*.distignore` file.
7. If you want release-time translation template generation, set `POT_FILE` to a repo-relative path now so release prep can generate the file when missing. Also add a `Domain Path` plugin header, typically `/languages/`, if `POT_FILE` is configured or the repo will contain a `languages/` directory.
8. Run `bash .wp-plugin-base/scripts/update/sync_child_repo.sh`.
9. Run `bash .wp-plugin-base/scripts/ci/validate_project.sh`.
10. Commit the vendored foundation, config, and generated managed files, including `.github/dependabot.yml`.
11. Add GitHub Actions settings. Configure `SVN_USERNAME` and `SVN_PASSWORD` as GitHub Actions deployment-environment secrets if WordPress.org deploy will be enabled. Set `WP_ORG_DEPLOY_ENABLED=true` only if WordPress.org deploy should be enabled, as either a GitHub Actions repository variable or a GitHub Actions environment variable.
12. If WooCommerce.com deploy is needed, set `WOOCOMMERCE_COM_DEPLOY_ENABLED=true` and add `WOO_COM_USERNAME`/`WOO_COM_APP_PASSWORD` deployment-environment secrets.
13. In GitHub, open `Settings` -> `Actions` -> `General`.
14. Under `Actions permissions`, choose `Allow OWNER, and select non-OWNER, actions and reusable workflows`.
15. Allow GitHub-authored actions and only the specific non-GitHub actions documented in [Security model](security-model.md).
16. Enable `Require actions to be pinned to a full-length commit SHA`.
17. Under `Workflow permissions`, select `Read and write permissions`.
18. Enable `Allow GitHub Actions to create and approve pull requests` so `prepare-release` and `update-foundation` can open PRs.
19. If that option is greyed out, ask an organization owner to enable it in the organization under `Settings` -> `Actions` -> `General` first.
20. If you plan to use the automated foundation self-update workflow, confirm that GitHub Actions in your project can access releases from `FOUNDATION_REPOSITORY`.
21. If you plan to use WordPress.org deploy, protect the `PRODUCTION_ENVIRONMENT` environment in GitHub and require at least one reviewer before deployments can access secrets. `PRODUCTION_ENVIRONMENT` defaults to `production` when unset.
22. Leave Dependabot enabled so weekly GitHub Actions update PRs can keep the pinned action SHAs current.

## Default Layout Assumptions

The simplest setup assumes:

- the main plugin file is at repo root
- `readme.txt` is at repo root
- the plugin version is stored in the plugin header and `readme.txt`
- changelog sections use `= x.y.z =`
- packaging can start from repo root and exclude development files via the managed distignore path
- `packages/` and `routes/` are build-time workspaces and are excluded from the default install ZIP and translation scan unless you explicitly include them

If your repo matches those assumptions, the only optional value most projects need is `WORDPRESS_ORG_SLUG`.

Set `CODEOWNERS_REVIEWERS` if you want the generated `.github/CODEOWNERS` file to require review on workflow, script, and dependency-policy changes.

If you enable `WORDPRESS_READINESS_ENABLED=true`, treat that as a stricter contract, not a cosmetic toggle. The plugin file and `readme.txt` must already satisfy the WordPress.org-style metadata checks before validation will pass.

## Local Validation

Before you rely on the generated workflows, validate the local contract:

```bash
bash .wp-plugin-base/scripts/ci/validate_project.sh
```

That command validates:

- required config keys and value formats
- the plugin main file and `readme.txt` paths
- the generated managed-file surface, including root managed files, the configured suppressions file, and any enabled quality/security/QIT pack files
- PHP and JavaScript syntax
- workflow policy compliance
- version alignment
- release branch metadata when you provide a branch name
- ZIP package creation

Workflow files must use the `.yml` extension. `.yaml` workflow files are rejected by project and foundation validation.

For WordPress.org deploy-enabled repos, local validation warns when GitHub environment protection cannot be queried yet. The generated CI workflows enforce that check strictly once the repository is running in GitHub Actions.

The manual `release.yml` recovery workflow skips WordPress.org redeploy by default so an existing SVN tag is not rewritten during a repair run. Only set `WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY=true` for an intentional break-glass redeploy of the latest repository release tag. Use `release.yml` and `woocommerce-status.yml` to repair downstream distribution channels after a publish.
