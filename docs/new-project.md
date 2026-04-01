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
   Keep `ZIP_FILE` as a simple filename such as `example-plugin.zip`, not a path.
6. Run `bash .wp-plugin-base/scripts/update/sync_child_repo.sh`.
7. Run `bash .wp-plugin-base/scripts/ci/validate_project.sh`.
8. Commit the vendored foundation, config, and generated managed files, including `.github/dependabot.yml`.
9. Add GitHub Actions settings:
   - `SVN_USERNAME` as a GitHub Actions secret on the deployment environment if WordPress.org deploy will be enabled
   - `SVN_PASSWORD` as a GitHub Actions secret on the deployment environment if WordPress.org deploy will be enabled
   - `WP_ORG_DEPLOY_ENABLED=true` only if WordPress.org deploy should be enabled, as either a GitHub Actions repository variable or a GitHub Actions environment variable
10. In GitHub, open `Settings` -> `Actions` -> `General`.
11. Under `Actions permissions`, choose `Allow OWNER, and select non-OWNER, actions and reusable workflows`.
12. Allow GitHub-authored actions and only the specific non-GitHub actions documented in [Security model](security-model.md).
13. Enable `Require actions to be pinned to a full-length commit SHA`.
14. Under `Workflow permissions`, select `Read and write permissions`.
15. Enable `Allow GitHub Actions to create and approve pull requests` so `prepare-release` and `update-foundation` can open PRs.
16. If that option is greyed out, ask an organization owner to enable it in the organization under `Settings` -> `Actions` -> `General` first.
17. If you plan to use the automated foundation self-update workflow, confirm that GitHub Actions in your project can access releases from `FOUNDATION_REPOSITORY`.
18. If you plan to use WordPress.org deploy, protect the `PRODUCTION_ENVIRONMENT` environment in GitHub and require at least one reviewer before deployments can access secrets.
19. Leave Dependabot enabled so weekly GitHub Actions update PRs can keep the pinned action SHAs current.

## Default Layout Assumptions

The simplest setup assumes:

- the main plugin file is at repo root
- `readme.txt` is at repo root
- the plugin version is stored in the plugin header and `readme.txt`
- changelog sections use `= x.y.z =`
- packaging can start from repo root and exclude development files via `.distignore`

If your repo matches those assumptions, the only optional value most projects need is `WORDPRESS_ORG_SLUG`.

Set `CODEOWNERS_REVIEWERS` if you want the generated `.github/CODEOWNERS` file to require review on workflow, script, and dependency-policy changes.

## Local Validation

Before you rely on the generated workflows, validate the local contract:

```bash
bash .wp-plugin-base/scripts/ci/validate_project.sh
```

That command validates:

- required config keys and value formats
- main plugin and readme paths
- PHP and JavaScript syntax
- workflow policy compliance
- version alignment
- release branch metadata when you provide a branch name
- ZIP package creation
