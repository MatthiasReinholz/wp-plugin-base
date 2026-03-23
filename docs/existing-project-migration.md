# Existing Project Migration

Use this path when migrating an existing plugin repository onto `wp-plugin-base`.

## Recommended Migration Order

1. Add the foundation repo into `.wp-plugin-base/`.
2. Create `.wp-plugin-base.env`.
3. Compare the existing repo against the foundation defaults:
   - plugin main file location
   - readme location
   - version constant name
   - POT file location
   - package include and exclude rules
4. Set the minimum required overrides in `.wp-plugin-base.env`.
5. Run `bash .wp-plugin-base/scripts/update/sync_child_repo.sh`.
6. Replace any old local CI or release scripts with thin shims or direct calls into `.wp-plugin-base/scripts/...`.
7. Run the shared script suite locally:
   - `bash .wp-plugin-base/scripts/ci/check_versions.sh`
   - `bash .wp-plugin-base/scripts/ci/check_release_branch.sh release/x.y.z`
   - `bash .wp-plugin-base/scripts/ci/lint_php.sh`
   - `bash .wp-plugin-base/scripts/ci/lint_js.sh`
   - `bash .wp-plugin-base/scripts/ci/build_zip.sh`
8. Review the generated ZIP to confirm that only installable plugin files are included.
9. Merge only after the repo-local packaging and release semantics still match the previous behavior.
10. In GitHub repository settings, enable `Allow GitHub Actions to create and approve pull requests` so `prepare-release` and `update-foundation` can open PRs.
11. If that setting is greyed out, ask an organization owner to allow it at the organization level first.
12. If you plan to use automated foundation self-updates, confirm that GitHub Actions in the repository can access releases from `FOUNDATION_REPOSITORY`.

## Common Migration Adjustments

- Set `VERSION_CONSTANT_NAME` when the plugin stores its version in a named constant.
- Set `POT_FILE` and `POT_PROJECT_NAME` when the translation template exists and should be updated during release prep.
- Set `PACKAGE_INCLUDE` when packaging must be restricted to a specific subset of repo files.
- Set `PACKAGE_EXCLUDE` when repo-specific development paths must stay out of the install ZIP.

## Safety Checks

Before enabling WordPress.org deploy, confirm:

- `WORDPRESS_ORG_SLUG` is correct
- `WP_ORG_DEPLOY_ENABLED` is still unset or `false` in GitHub Actions repository variables or environment variables during migration
- the generated ZIP matches the existing install artifact shape
