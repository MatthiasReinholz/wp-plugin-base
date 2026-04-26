# Managed Files

These files are intended to be generated from foundation templates in your project:

- `.editorconfig`
- `.gitattributes`
- `.gitignore`
- `.distignore`, or the path configured by `DISTIGNORE_FILE`
- `AGENTS.md`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `uninstall.php.example`
- `.github/dependabot.yml`, `.github/CODEOWNERS`, and `.github/workflows/*.yml` when `AUTOMATION_PROVIDER=github`
- `.gitlab-ci.yml` and `.gitlab/CODEOWNERS` when `AUTOMATION_PROVIDER=gitlab`
- `.phpcs.xml.dist`, `phpstan.neon.dist`, and `phpstan.neon` when `WORDPRESS_QUALITY_PACK_ENABLED=true` (full quality pack)
- `phpunit.xml.dist`, `tests/bootstrap.php`, `tests/wp-plugin-base/PluginLoadsTest.php`, `.wp-plugin-base-quality-pack/composer.json`, `.wp-plugin-base-quality-pack/composer.lock`, and `tests/wp-plugin-base/bootstrap-child.php` when either `WORDPRESS_QUALITY_PACK_ENABLED=true` or `PHP_RUNTIME_MATRIX` is set with `PHP_RUNTIME_MATRIX_MODE=strict` (PHPUnit bridge path)
- `.phpcs-security.xml.dist` and `.wp-plugin-base-security-pack/**` when `WORDPRESS_SECURITY_PACK_ENABLED=true`
- `.github/workflows/woocommerce-qit.yml` when `WOOCOMMERCE_QIT_ENABLED=true`
- `.github/workflows/woocommerce-status.yml` when `WOOCOMMERCE_COM_PRODUCT_ID` is configured (status diagnostics file; the workflow self-skips unless `WOOCOMMERCE_COM_DEPLOY_ENABLED=true`)
- `docs/github-release-updater.md`, `lib/wp-plugin-base/wp-plugin-base-runtime-updater.php`, `lib/wp-plugin-base/wp-plugin-base-github-updater.php`, and `lib/wp-plugin-base/plugin-update-checker/**` when `PLUGIN_RUNTIME_UPDATE_PROVIDER!=none`
- `docs/rest-operations-pack.md` and `lib/wp-plugin-base/rest-operations/**` when `REST_OPERATIONS_PACK_ENABLED=true`
- `docs/admin-ui-pack.md`, `lib/wp-plugin-base/admin-ui/**`, and `.wp-plugin-base-admin-ui/build.sh` / `.wp-plugin-base-admin-ui/shared/**` when `ADMIN_UI_PACK_ENABLED=true`
- `.github/workflows/simulate-release.yml` when `SIMULATE_RELEASE_WORKFLOW_ENABLED=true`
- `.wp-plugin-base-security-suppressions.json`, or the path configured by `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE`, when absent

Do not hand-edit those files in your project unless you are intentionally diverging from the foundation. If you need a permanent change, make it in `wp-plugin-base` and resync.

`bash .wp-plugin-base/scripts/ci/validate_project.sh` treats that managed surface as part of the child-repo contract. If one of those files is missing after sync, or if a required file path has been replaced with a directory or another non-file entry, project validation fails and points back to `sync_child_repo.sh`.

GitHub repos receive the managed GitHub workflow set plus optional Dependabot automation. GitLab repos receive a managed `.gitlab-ci.yml` pipeline that covers validation, release preparation, release publication, and foundation updates. Managed CODEOWNERS files are optional on both hosts. Each downstream repo should select one host profile; mixed GitHub/GitLab automation in one repo is out of contract.

If a project does not already have a `CHANGELOG.md`, sync also seeds one from the child template. After that initial creation, the project owns its changelog content.

The managed distignore file excludes common development-only paths (`/docs`, `/scripts`, `/tests`, `/packages`, and `/routes`) by default so build-only workspaces stay out of the install ZIP and translation scan. If one of those directories belongs in the shipped plugin, add it explicitly through `PACKAGE_INCLUDE` and remove only the paths that should stay excluded through `PACKAGE_EXCLUDE`.

If a project does not already have the configured suppressions file, sync seeds it with an empty suppression set. After that initial creation, the project owns suppression entries and justifications.

The REST operations pack and admin UI pack also seed child-owned files the first time they are enabled. Those seeded files remain project-owned after creation, but project validation still treats them as required pack surface while the pack is enabled.

Managed automation files use `.yml` on GitHub and `.gitlab-ci.yml` on GitLab. The package builder excludes both GitHub and GitLab automation metadata from the shipped plugin ZIP.
