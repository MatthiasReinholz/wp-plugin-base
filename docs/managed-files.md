# Managed Files

These files are intended to be generated from foundation templates in your project:

- `.github/dependabot.yml`
- `.github/CODEOWNERS` when `CODEOWNERS_REVIEWERS` is set
- `.github/workflows/ci.yml`
- `.github/workflows/prepare-release.yml`
- `.github/workflows/finalize-release.yml`
- `.github/workflows/release.yml`
- `.github/workflows/update-foundation.yml`
- `.editorconfig`
- `.gitattributes`
- `.gitignore`
- `.distignore`, or the path configured by `DISTIGNORE_FILE`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `uninstall.php.example`
- `.phpcs.xml.dist`, `phpstan.neon.dist`, `phpunit.xml.dist`, `tests/bootstrap.php`, `tests/wp-plugin-base/PluginLoadsTest.php`, and `.wp-plugin-base-quality-pack/**` when `WORDPRESS_QUALITY_PACK_ENABLED=true`
- `.phpcs-security.xml.dist` and `.wp-plugin-base-security-pack/**` when `WORDPRESS_SECURITY_PACK_ENABLED=true`
- `.github/workflows/woocommerce-qit.yml` when `WOOCOMMERCE_QIT_ENABLED=true`
- `.github/workflows/woocommerce-status.yml` when `WOOCOMMERCE_COM_PRODUCT_ID` is configured (status diagnostics file; the workflow self-skips unless `WOOCOMMERCE_COM_DEPLOY_ENABLED=true`)
- `docs/github-release-updater.md`, `lib/wp-plugin-base/wp-plugin-base-github-updater.php`, and `lib/wp-plugin-base/plugin-update-checker/**` when `GITHUB_RELEASE_UPDATER_ENABLED=true`
- `docs/rest-operations-pack.md` and `lib/wp-plugin-base/rest-operations/**` when `REST_OPERATIONS_PACK_ENABLED=true`
- `docs/admin-ui-pack.md`, `lib/wp-plugin-base/admin-ui/**`, and `.wp-plugin-base-admin-ui/build.sh` / `.wp-plugin-base-admin-ui/shared/**` when `ADMIN_UI_PACK_ENABLED=true`
- `.github/workflows/simulate-release.yml` when `SIMULATE_RELEASE_WORKFLOW_ENABLED=true`
- `.wp-plugin-base-security-suppressions.json`, or the path configured by `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE`, when absent

Do not hand-edit those files in your project unless you are intentionally diverging from the foundation. If you need a permanent change, make it in `wp-plugin-base` and resync.

`bash .wp-plugin-base/scripts/ci/validate_project.sh` treats that managed surface as part of the child-repo contract. If one of those files is missing after sync, or if a required file path has been replaced with a directory or another non-file entry, project validation fails and points back to `sync_child_repo.sh`.

`finalize-release.yml` is the standard automated publish path. `release.yml` is the manual recovery workflow for an already existing tag. `.github/dependabot.yml` keeps GitHub Actions pins moving through reviewable PRs. `.github/CODEOWNERS` is optional so projects can choose whether workflow, script, and dependency-file changes require explicit reviewer ownership.

If a project does not already have a `CHANGELOG.md`, sync also seeds one from the child template. After that initial creation, the project owns its changelog content.

The managed distignore file excludes repo-root `packages/` and `routes/` by default so build-only workspaces stay out of the install ZIP and translation scan. If either directory belongs in the shipped plugin, add it explicitly through `PACKAGE_INCLUDE` and remove only the paths that should stay excluded through `PACKAGE_EXCLUDE`.

If a project does not already have the configured suppressions file, sync seeds it with an empty suppression set. After that initial creation, the project owns suppression entries and justifications.

The REST operations pack and admin UI pack also seed child-owned files the first time they are enabled. Those seeded files remain project-owned after creation, but project validation still treats them as required pack surface while the pack is enabled.

Managed workflow files use the `.yml` extension. `.yaml` workflow files are rejected by project and foundation validation.
