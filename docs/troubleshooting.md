# Troubleshooting

## Local Validation Fails Immediately

Run the shared local validation entrypoint first:

```bash
bash .wp-plugin-base/scripts/ci/validate_project.sh
```

If that fails before any repo checks run, the most common causes are:

- a missing command such as `ruby`, `jq`, `rsync`, `zip`, or `unzip`
- an invalid `.wp-plugin-base.env` value
- a missing `MAIN_PLUGIN_FILE` or `README_FILE`
- an invalid `POT_FILE` path or parent directory when POT generation is configured
- forbidden repository files such as `.DS_Store`, `Thumbs.db`, `.idea/`, `.vscode/`, or transient debug logs

The validation scripts now fail fast and identify the missing tool or invalid config key directly. Unknown `.wp-plugin-base.env` keys are rejected so typos do not silently degrade behavior.

If foundation validation passes in `fast-local` mode but you want CI-like tool enforcement locally, rerun:

```bash
bash scripts/foundation/validate.sh --mode strict-local
```

`gh`, `svn`, and similar tools are still required for release, update, or deploy flows, but they are not baseline prerequisites for `validate_project.sh`.

If you are bootstrapping a blank repo, create the plugin main file and `readme.txt` before the first sync. The foundation expects those files to exist before validation can pass.

## Pull Request Creation Fails

Some foundation workflows create pull requests automatically, including:

- `prepare-release`
- `prepare-foundation-release`
- `update-foundation`

If those workflows fail when they try to open a pull request, check the GitHub Actions repository setting named `Allow GitHub Actions to create and approve pull requests`.

### Case 1: The Setting Is Available But Disabled

If the setting is visible in the repository settings, enable it:

1. Open your repository on GitHub.
2. Go to `Settings` -> `Actions` -> `General`.
3. Under `Workflow permissions`, select `Read and write permissions`.
4. Enable `Allow GitHub Actions to create and approve pull requests`.
5. Save the change and rerun the failed workflow.

Without that setting, workflows can still run, but workflows that use the foundation's `gh pr` automation cannot open or update pull requests.

### Case 2: The Setting Is Greyed Out

If the setting is greyed out, the repository is usually inheriting an organization-level restriction.

In that case, an organization owner must allow it first:

1. Open the organization on GitHub.
2. Go to `Settings` -> `Actions` -> `General`.
3. Allow repositories in the organization to let GitHub Actions create and approve pull requests.
4. Return to the repository settings and enable the repository-level setting if GitHub still requires it there.

If you do not have organization admin access, ask an organization owner to make that change.

## Readiness Fails On Deployment Environment Protection

When `WP_ORG_DEPLOY_ENABLED=true`, CI/release readiness now enforces deployment environment protection in strict mode.

If readiness fails with reviewer-protection errors:

- confirm the GitHub environment named by `PRODUCTION_ENVIRONMENT` exists in the repository; the config defaults to `production` when unset
- require at least one reviewer on that environment
- ensure the readiness step has `GH_TOKEN` available so it can query environment protection rules

## Install ZIP Is Missing Nested Files

If the generated ZIP drops files from `packages/` or `routes/`, check the package include and exclude settings first.

- `PACKAGE_INCLUDE` and `PACKAGE_EXCLUDE` are repo-relative paths
- absolute paths in `PACKAGE_INCLUDE`, `PACKAGE_EXCLUDE`, or `DISTIGNORE_FILE` are rejected
- `DISTIGNORE_FILE` must point to a `*.distignore` file, not another managed project file
- `packages/` and `routes/` are excluded by default
- include those directories explicitly only if they are part of the shipped plugin

If the ZIP root looks flattened, check that file entries in `PACKAGE_INCLUDE` are being preserved as repo-relative paths.

## Foundation Self-Update Cannot Open A PR

If `update-foundation` detects a newer version but fails during pull request creation, check both of these:

- `Allow GitHub Actions to create and approve pull requests` is enabled for the repository
- GitHub Actions in your repository can read releases from `FOUNDATION_REPOSITORY`

Both conditions are required for the automated update PR flow to work.
