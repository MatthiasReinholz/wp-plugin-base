# Existing Project Migration

Use this path when migrating an existing plugin repository onto `wp-plugin-base`.

Each downstream project should choose one automation host profile. The only normal cross-host case is `FOUNDATION_RELEASE_SOURCE_*`, which describes where `wp-plugin-base` itself is officially published.

## Recommended Migration Order

1. Add the foundation repo into `.wp-plugin-base/`.
2. Create `.wp-plugin-base.env` from `.wp-plugin-base/templates/child/.wp-plugin-base.env.example`.
3. Compare the existing repo against the foundation defaults:
   - plugin main file location
   - readme location
   - version constant name
   - POT file location
   - package include and exclude rules
   - whether `packages/` or `routes/` are part of the shipped plugin or only build-time workspaces
4. Set the minimum required overrides in `.wp-plugin-base.env`.
   If you need a custom suppression file path, set `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE` before your first sync so bootstrap seeds the configured file.
   If you are migrating to readiness mode, make sure the plugin header and `readme.txt` already satisfy the stricter WordPress metadata contract.
5. Run `bash .wp-plugin-base/scripts/update/sync_child_repo.sh`.
6. Replace any old local CI or release scripts with thin shims or direct calls into `.wp-plugin-base/scripts/...`.
7. Run `bash .wp-plugin-base/scripts/ci/validate_project.sh`.
8. Optionally validate release-branch metadata with `bash .wp-plugin-base/scripts/ci/validate_project.sh .wp-plugin-base.env release/x.y.z`.
9. Review the generated ZIP to confirm that only installable plugin files are included and that nested file paths are preserved.
10. Merge only after the repo-local packaging and release semantics still match the previous behavior.
11. Configure automation permissions for the selected host so release preparation and foundation updates can push branches and open PRs or MRs.
12. If the host supports action or pipeline allowlists, restrict them to the pinned tools documented in [Security model](security-model.md).
13. If the host supports SHA pinning or protected includes, require those protections for privileged automation.
14. If you plan to use automated foundation self-updates, confirm that the selected automation host can access releases from `FOUNDATION_RELEASE_SOURCE_REFERENCE`.
15. If WordPress.org deploy will remain enabled, move `SVN_USERNAME` and `SVN_PASSWORD` into protected CI secrets and protect the selected deployment environment with at least one reviewer. `PRODUCTION_ENVIRONMENT` defaults to `production` when unset.

## Common Migration Adjustments

- Treat `tests/bootstrap.php` as managed infrastructure when the PHPUnit bridge is enabled (`WORDPRESS_QUALITY_PACK_ENABLED=true` or `PHP_RUNTIME_MATRIX` + `PHP_RUNTIME_MATRIX_MODE=strict`). Move child-specific PHPUnit preloads/support-class `require` statements into `tests/wp-plugin-base/bootstrap-child.php`, which is child-owned and preserved across syncs.
- Set `VERSION_CONSTANT_NAME` when the plugin stores its version in a named constant.
- Set `POT_FILE` and `POT_PROJECT_NAME` when the translation template exists and should be updated during release prep. Translation support also requires a `Domain Path` plugin header, typically `/languages/`, when `POT_FILE` is configured or the repo contains a `languages/` directory.
- Keep project-local `.gitignore` aligned with the managed ignore template so transient files such as `.DS_Store`, editor metadata, and debug logs never enter the repository.
- Use `.wp-plugin-base-security-suppressions.json` only for intentional public endpoints and always require explicit written justification for each suppression.
- Set `PACKAGE_INCLUDE` when packaging must be restricted to a specific subset of repo files.
- Set `PACKAGE_EXCLUDE` when repo-specific development paths must stay out of the install ZIP.
- Keep `PACKAGE_INCLUDE`, `PACKAGE_EXCLUDE`, and `DISTIGNORE_FILE` repo-relative so nested files stay nested in the ZIP. `DISTIGNORE_FILE` must point to a `*.distignore` file.
- Include `packages/` and `routes/` explicitly only when they are part of the shipped plugin; they are excluded from the default install ZIP and translation scan otherwise.
- Treat `WORDPRESS_READINESS_ENABLED=true` as a contract change, not a cosmetic flag. It turns on the stricter metadata checks described in the readiness docs.
- Treat `WORDPRESS_QUALITY_PACK_ENABLED=true` and `WORDPRESS_SECURITY_PACK_ENABLED=true` as readiness submodes, not standalone toggles. Both require `WORDPRESS_READINESS_ENABLED=true`.

## Host-Specific Guidance

### Staying On GitHub

If the project already lives on GitHub and will stay there, no host migration is required. Legacy GitHub aliases such as `FOUNDATION_REPOSITORY`, `GITHUB_RELEASE_UPDATER_ENABLED`, and `GITHUB_RELEASE_UPDATER_REPO_URL` remain accepted.

### Moving From GitHub To GitLab

When the downstream repo moves from GitHub to GitLab, update the downstream host-facing keys together:

- `AUTOMATION_PROVIDER=gitlab`
- `AUTOMATION_API_BASE=https://gitlab.example.com/api/v4` when self-managed, or leave the default for `gitlab.com`
- `PLUGIN_RUNTIME_UPDATE_PROVIDER=gitlab-release` only if you also want the plugin runtime updater and the downstream project will publish releases from GitLab
- `PLUGIN_RUNTIME_UPDATE_SOURCE_URL=https://gitlab.example.com/group/project` for host-backed runtime updates

Do not treat this as a mixed-host downstream setup. If the project moves to GitLab, the downstream automation host and any host-backed runtime updater should move with it. `FOUNDATION_RELEASE_SOURCE_*` may remain on GitHub if the authoritative `wp-plugin-base` source still publishes there.

## Safety Checks

Before enabling WordPress.org deploy, confirm:

- `WORDPRESS_ORG_SLUG` is correct
- `WP_ORG_DEPLOY_ENABLED` is still unset or `false` in GitHub Actions repository variables or environment variables during migration
- `WP_ORG_DEPLOY_ENABLED` is still unset or `false` in your selected CI host during migration
- the generated ZIP matches the existing install artifact shape
- the plugin main file and `readme.txt` already exist before validation
- the selected CI host policy matches the allowlist and pinning rules documented in [Security model](security-model.md)

If you later need to repair a published host release manually, use the host-specific repair flow. GitHub uses the manual `release.yml` workflow for stable tags and the prerelease-only `publish-tag-release.yml` workflow for trusted prerelease tags. GitLab uses the tagged `release` job from the managed `.gitlab-ci.yml`. Both paths verify the existing tag and skip WordPress.org redeploy by default so the existing SVN tag is not rewritten accidentally.
Downstream channels can fail after host-release publication. On GitHub, pair release repair with `woocommerce-status.yml` when WooCommerce.com is enabled. On GitLab, inspect Woo vendor/QIT status directly because there is no separate status workflow.

## Release-Order Behavior Change

Current release flow is host-release-first: the selected Git host publishes first, then downstream channel deploy steps run after that.

If your previous internal process expected WordPress.org deploy to gate tag publication, treat this as an operational behavior change and update your release runbooks accordingly.

## PHPUnit Bootstrap Migration

If an older child repository keeps custom PHPUnit preloads inside `tests/bootstrap.php`, move that child logic before your first sync.

Use this ownership model:

- `tests/bootstrap.php`: managed by `wp-plugin-base`; sync can replace it
- `tests/wp-plugin-base/bootstrap-child.php`: child-owned overlay for project-specific preloads, hooks, and support-class bootstrapping

If sync warns that managed bootstrap customizations were detected, move those custom `require` statements into `tests/wp-plugin-base/bootstrap-child.php` and rerun sync plus project validation.
