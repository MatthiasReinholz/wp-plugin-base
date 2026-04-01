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
7. Run `bash .wp-plugin-base/scripts/ci/validate_project.sh`.
8. Optionally validate release-branch metadata with `bash .wp-plugin-base/scripts/ci/validate_project.sh .wp-plugin-base.env release/x.y.z`.
9. Review the generated ZIP to confirm that only installable plugin files are included.
10. Merge only after the repo-local packaging and release semantics still match the previous behavior.
11. In GitHub, open `Settings` -> `Actions` -> `General`.
12. Under `Actions permissions`, choose `Allow OWNER, and select non-OWNER, actions and reusable workflows`.
13. Allow GitHub-authored actions and only the specific non-GitHub actions documented in [Security model](security-model.md).
14. Enable `Require actions to be pinned to a full-length commit SHA`.
15. Under `Workflow permissions`, select `Read and write permissions`.
16. Enable `Allow GitHub Actions to create and approve pull requests` so `prepare-release` and `update-foundation` can open PRs.
17. If that option is greyed out, ask an organization owner to enable it in the organization under `Settings` -> `Actions` -> `General` first.
18. If you plan to use automated foundation self-updates, confirm that GitHub Actions in the repository can access releases from `FOUNDATION_REPOSITORY`.
19. If WordPress.org deploy will remain enabled, move `SVN_USERNAME` and `SVN_PASSWORD` into environment secrets and protect the selected deployment environment with at least one reviewer.

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
- the GitHub Actions policy for the repository matches the allowlist and pinning rules documented in [Security model](security-model.md)
