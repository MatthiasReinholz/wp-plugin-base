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
bash scripts/foundation/bootstrap_strict_local.sh "$PWD/.wp-plugin-base-tools"
export PATH="$PWD/.wp-plugin-base-tools:$PATH"
bash scripts/foundation/validate.sh --mode strict-local
```

`gh`, `svn`, and similar tools are still required for release, update, or deploy flows, but they are not baseline prerequisites for `validate_project.sh`.

If you are bootstrapping a blank repo, create the plugin main file and `readme.txt` before the first sync. The foundation expects those files to exist before validation can pass.

## Change Request Creation Fails

Some foundation automation flows create change requests automatically, including:

- `prepare-release`
- `prepare-foundation-release`
- `update-foundation`

Use the troubleshooting path that matches the selected automation host.

### GitHub

If GitHub-hosted workflows fail when they try to open a pull request, check the GitHub Actions repository setting named `Allow GitHub Actions to create and approve pull requests`.

1. Open your repository on GitHub.
2. Go to `Settings` -> `Actions` -> `General`.
3. Under `Workflow permissions`, select `Read and write permissions`.
4. Enable `Allow GitHub Actions to create and approve pull requests`.
5. Save the change and rerun the failed workflow.

Without that setting, workflows can still run, but workflows that use the foundation's `gh pr` automation cannot open or update GitHub pull requests.

If the setting is greyed out, the repository is usually inheriting an organization-level restriction.

In that case, an organization owner must allow it first:

1. Open the organization on GitHub.
2. Go to `Settings` -> `Actions` -> `General`.
3. Allow repositories in the organization to let GitHub Actions create and approve pull requests.
4. Return to the repository settings and enable the repository-level setting if GitHub still requires it there.

If you do not have organization admin access, ask an organization owner to make that change.

If the error mentions workflow-file permissions, the automation token likely cannot push or open a PR that includes `.github/workflows/*` changes. Grant the token workflow scope or remove the workflow-file edits from that change request.

Preferred recovery path:

1. create a narrowly scoped GitHub token that can update workflow files
2. store it as the repository secret `WP_PLUGIN_BASE_PR_TOKEN`
3. rerun the failed `update-foundation` or `update-external-dependencies` workflow

The managed GitHub update workflows prefer `WP_PLUGIN_BASE_PR_TOKEN` for PR creation when it is configured and otherwise fall back to `github.token`.

### GitLab

If GitLab-hosted automation fails to open a merge request:

- confirm `GITLAB_TOKEN` or `CI_JOB_TOKEN` is available to the job
- confirm that token can push branches and create merge requests in the project
- confirm `AUTOMATION_API_BASE` points at the correct GitLab API base for the selected instance
- if you use a self-managed instance, add the Git host to `TRUSTED_GIT_HOSTS`

## Readiness Fails On Deployment Environment Protection

When `WP_ORG_DEPLOY_ENABLED=true`, CI/release readiness now enforces deployment environment protection in strict mode.

If readiness fails with reviewer-protection errors:

- on GitHub: confirm the environment named by `PRODUCTION_ENVIRONMENT` exists in the repository, require at least one reviewer, and ensure the readiness step has `GH_TOKEN`
- on GitLab: confirm the environment named by `PRODUCTION_ENVIRONMENT` exists, protect it, require reviewer approval, and rerun only with `WP_PLUGIN_BASE_GITLAB_DEPLOY_ENV_ACKNOWLEDGED=true` once that review is complete

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
- automation on the selected host can read releases from `FOUNDATION_RELEASE_SOURCE_REFERENCE`

Both conditions are required for the automated update PR flow to work.
If the change request includes `.github/workflows/*` updates, also configure `WP_PLUGIN_BASE_PR_TOKEN` so the workflow can push those changes with a token that has workflow-write permission.
The managed `update-foundation` workflow now bootstraps release security tools (`cosign`, `syft`, companion binaries) before provenance verification. If you run `scripts/update/verify_foundation_release.sh` directly, install those tools first (for example via `scripts/release/install_release_security_tools.sh`).

## Post-Sync PHPUnit Bootstrap Regressions

If CI starts failing after `sync_child_repo.sh` with errors such as `Class not found` or missing test bootstrap support classes, check whether child-specific PHPUnit preload logic was stored in `tests/bootstrap.php`.

`tests/bootstrap.php` is managed by `wp-plugin-base` and can be overwritten on sync. Child-specific PHPUnit preloads belong in `tests/wp-plugin-base/bootstrap-child.php`, which is child-owned.

Recovery:

1. Move project-specific `require` statements and preload hooks from `tests/bootstrap.php` into `tests/wp-plugin-base/bootstrap-child.php`.
2. Rerun `bash .wp-plugin-base/scripts/update/sync_child_repo.sh`.
3. Rerun `bash .wp-plugin-base/scripts/ci/validate_project.sh`.

## External Dependency Updater Workflow Fails

The foundation's external dependency updater lives at `.github/workflows/update-plugin-check.yml` (display name: `update-external-dependencies`).

If it fails:

1. confirm the failing `dependency_id` from the matrix job title
2. rerun the workflow once to rule out transient network failures
3. validate local contracts:
   - `bash scripts/ci/validate_dependency_inventory.sh`
   - `bash scripts/foundation/test_dependency_inventory.sh`
   - `bash scripts/ci/audit_workflows.sh`
4. if only one dependency handler fails, inspect `scripts/update/prepare_external_dependency_update.sh` branch logic for that `dependency_id`
5. confirm expected hosts are allowlisted if a new upstream endpoint was introduced

## Finalize Release Failed In Distribution Channels

The selected host release flow publishes the Git tag/release first, then runs downstream channel deploy steps (WordPress.org and WooCommerce.com when enabled). A channel failure can therefore happen after host-release publication; the workflow still ends failed.

Repair path:

1. on GitHub, run `release.yml` for the existing release tag
2. on GitLab, rerun the tagged `release` job from the managed `.gitlab-ci.yml`
3. review WordPress.org/WooCommerce.com channel logs
4. on GitHub, run `woocommerce-status.yml` when Woo is enabled
5. rerun the same host-specific repair path until the failed channel succeeds or reports already-live state

If a tag with the release version exists on a different commit, stop and resolve the mismatch manually before retrying automated release flows.

## WooCommerce.com Channel Failures

Common WooCommerce.com-specific failures and actions:

1. `Woo:` header mismatch or missing in packaged plugin file:
   fix the plugin header to `Woo: <product_id>:<hash>` and ensure `<product_id>` matches `WOOCOMMERCE_COM_PRODUCT_ID`.
2. Credential or auth errors:
   regenerate the Woo WordPress application password and update `WOO_COM_APP_PASSWORD` in deployment-environment secrets.
3. API timeout or transport error:
   rerun release repair and, if needed, increase `WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS`.
4. QIT rejection after queue acceptance:
   inspect Woo vendor/QIT diagnostics, fix package issues, then rerun the same host-specific release repair path for the same tag.

See:

- [WooCommerce.com distribution](distribution-woocommerce-com.md)
- [Release model](release-model.md)
