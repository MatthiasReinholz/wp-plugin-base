# Existing Project Migration

Use this path when migrating an existing plugin repository onto `wp-plugin-base`.

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
11. In GitHub, open `Settings` -> `Actions` -> `General`.
12. Under `Actions permissions`, choose `Allow OWNER, and select non-OWNER, actions and reusable workflows`.
13. Allow GitHub-authored actions and only the specific non-GitHub actions documented in [Security model](security-model.md).
14. Enable `Require actions to be pinned to a full-length commit SHA`.
15. Under `Workflow permissions`, select `Read and write permissions`.
16. Enable `Allow GitHub Actions to create and approve pull requests` so `prepare-release` and `update-foundation` can open PRs.
17. If that option is greyed out, ask an organization owner to enable it in the organization under `Settings` -> `Actions` -> `General` first.
18. If you plan to use automated foundation self-updates, confirm that GitHub Actions in the repository can access releases from `FOUNDATION_REPOSITORY`.
19. If WordPress.org deploy will remain enabled, move `SVN_USERNAME` and `SVN_PASSWORD` into deployment-environment secrets and protect the selected deployment environment with at least one reviewer. `PRODUCTION_ENVIRONMENT` defaults to `production` when unset.

## Common Migration Adjustments

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

## Safety Checks

Before enabling WordPress.org deploy, confirm:

- `WORDPRESS_ORG_SLUG` is correct
- `WP_ORG_DEPLOY_ENABLED` is still unset or `false` in GitHub Actions repository variables or environment variables during migration
- the generated ZIP matches the existing install artifact shape
- the plugin main file and `readme.txt` already exist before validation
- the GitHub Actions policy for the repository matches the allowlist and pinning rules documented in [Security model](security-model.md)

If you later need to repair a published GitHub release manually, `release.yml` verifies the existing tag and skips WordPress.org redeploy by default so the existing SVN tag is not rewritten accidentally.
Downstream channels can fail after GitHub release publication; use `release.yml` and `woocommerce-status.yml` as the post-publish channel repair path.

## Release-Order Behavior Change

Current release flow is GitHub-first: tag + GitHub release publish before downstream channel deploy steps.

If your previous internal process expected WordPress.org deploy to gate tag publication, treat this as an operational behavior change and update your release runbooks accordingly.
