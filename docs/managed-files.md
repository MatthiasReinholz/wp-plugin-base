# Managed Files

Foundation sync writes three kinds of child-repo surface:

- managed files, which are regenerated from foundation templates and should be changed upstream in `wp-plugin-base`
- seeded or child-owned files, which are preserved for project-specific customization outside any marked foundation-managed section
- generated local tooling state, which must never be committed or packaged

## Regenerated Managed Files

These files are regenerated from foundation templates:

- `.editorconfig`
- `.gitattributes`
- `.gitignore`
- `.distignore`, or the path configured by `DISTIGNORE_FILE`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `uninstall.php.example`
- `.github/dependabot.yml`, `.github/CODEOWNERS`, and `.github/workflows/*.yml` when `AUTOMATION_PROVIDER=github`
- `.gitlab-ci.yml` and `.gitlab/CODEOWNERS` when `AUTOMATION_PROVIDER=gitlab`
- `.phpcs.xml.dist` and `phpstan.neon.dist` when `WORDPRESS_QUALITY_PACK_ENABLED=true` (full quality pack)
- `phpunit.xml.dist`, `tests/bootstrap.php`, `tests/wp-plugin-base/BootstrapTest.php`, `tests/wp-plugin-base/PluginLoadsTest.php`, `.wp-plugin-base-quality-pack/composer.json`, and `.wp-plugin-base-quality-pack/composer.lock` when either `WORDPRESS_QUALITY_PACK_ENABLED=true` or `PHP_RUNTIME_MATRIX` is set with `PHP_RUNTIME_MATRIX_MODE=strict` (PHPUnit bridge path)
- `.phpcs-security.xml.dist`, `.wp-plugin-base-security-pack/composer.json`, and `.wp-plugin-base-security-pack/composer.lock` when `WORDPRESS_SECURITY_PACK_ENABLED=true`
- `.github/workflows/woocommerce-qit.yml` when `WOOCOMMERCE_QIT_ENABLED=true`
- `.github/workflows/woocommerce-status.yml` when `WOOCOMMERCE_COM_PRODUCT_ID` is configured (status diagnostics file; the workflow self-skips unless `WOOCOMMERCE_COM_DEPLOY_ENABLED=true`)
- `docs/github-release-updater.md`, `lib/wp-plugin-base/wp-plugin-base-runtime-updater.php`, `lib/wp-plugin-base/wp-plugin-base-github-updater.php`, and `lib/wp-plugin-base/plugin-update-checker/**` when `PLUGIN_RUNTIME_UPDATE_PROVIDER!=none`
- `docs/rest-operations-pack.md` and `lib/wp-plugin-base/rest-operations/**` when `REST_OPERATIONS_PACK_ENABLED=true`
- `docs/admin-ui-pack.md`, `lib/wp-plugin-base/admin-ui/**`, and `.wp-plugin-base-admin-ui/build.sh` / `.wp-plugin-base-admin-ui/shared/**` when `ADMIN_UI_PACK_ENABLED=true`
- `.github/workflows/simulate-release.yml` when `SIMULATE_RELEASE_WORKFLOW_ENABLED=true`

Do not hand-edit those files in your project unless you are intentionally diverging from the foundation. If you need a permanent change, make it in `wp-plugin-base` and resync.

`scripts/ci/list_managed_files.sh --mode validate` prints this regenerated managed surface. `--mode stage` includes the union of managed paths across hosts and packs, so tracked removals are staged, and also includes required seeded files so foundation-update automation can commit newly created child-owned files without treating them as managed.

`bash .wp-plugin-base/scripts/ci/validate_project.sh` treats that managed surface as part of the child-repo contract. If one of those files is missing after sync, or if a required file path has been replaced with a directory or another non-file entry, project validation fails and points back to `sync_child_repo.sh`.

GitHub repos receive the managed GitHub workflow set plus optional Dependabot automation. GitLab repos receive a managed `.gitlab-ci.yml` pipeline that covers validation, release preparation, release publication, and foundation updates. Managed CODEOWNERS files are optional on both hosts. Each downstream repo should select one host profile; mixed GitHub/GitLab automation in one repo is out of contract.

## Seeded Or Child-Owned Files

These files are created or maintained so the project can customize them safely:

- `AGENTS.md`: sync updates only the marked `wp-plugin-base` managed section. Project-specific agent instructions belong outside that section.
- `CHANGELOG.md`: seeded from the child template only when absent. After that initial creation, the project owns its changelog content.
- `.wp-plugin-base-security-suppressions.json`, or the path configured by `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE`: seeded when absent, then project-owned.
- `phpstan.neon`: seeded when the full quality pack is enabled, then project-owned. Use it for PHPStan paths, excludes, bootstrap files, and scan files.
- `tests/wp-plugin-base/bootstrap-child.php`: seeded when the PHPUnit bridge is enabled, then project-owned. Use it for project-specific PHPUnit preloads and support-class bootstrapping.
- REST operations and admin UI pack seed files, which remain project-owned after first creation.

The managed `phpunit.xml.dist` discovers `*Test.php` files under `tests/`. Keep foundation-managed baseline tests in `tests/wp-plugin-base/`, and place project-owned PHPUnit tests in a child-owned subtree such as `tests/php/`.

Packaging verifies that enabled REST/admin packs retain every managed runtime PHP file and their required child-owned bootstrap, even with custom `PACKAGE_INCLUDE` or `PACKAGE_EXCLUDE` settings. Pack documentation and admin build-tool seeds remain development-only.

The managed distignore file excludes common development-only paths (`/docs`, `/scripts`, `/tests`, `/packages`, and `/routes`) by default so build-only workspaces stay out of the install ZIP and translation scan. If one of those directories belongs in the shipped plugin, add it explicitly through `PACKAGE_INCLUDE` and remove only the paths that should stay excluded through `PACKAGE_EXCLUDE`.

## Local Generated State

These paths are local tooling state and must not be committed or packaged:

- `.wp-plugin-base-quality-pack/vendor/`
- `.wp-plugin-base-security-pack/vendor/`
- `.wp-plugin-base-admin-ui/node_modules/`
- root `node_modules/`
- `dist/`

The child template `.gitignore` ignores generated quality/security pack vendor directories, and `check_forbidden_files.sh` fails if generated pack vendor files are force-added to git.

Seeded files remain project-owned after creation, but project validation still treats required seed paths as present while their pack is enabled.

Managed automation files use `.yml` on GitHub and `.gitlab-ci.yml` on GitLab. The package builder excludes both GitHub and GitLab automation metadata from the shipped plugin ZIP.

## Child PHPCS rules

Project-specific PHPCS exclusions and compatibility exceptions belong in the optional
`.wp-plugin-base-quality-pack/phpcs-child.xml` ruleset. Create that child-owned file,
then run foundation sync to include it from the managed `.phpcs.xml.dist`.
Sync preserves its contents. Removing the overlay and syncing removes the include.
Keep exceptions narrow; generated admin asset metadata is already excluded by the foundation.

## Manifest And Rendering Contracts

`scripts/lib/managed_files.sh` is the shared authority for generation, validation, staging and disabled-file cleanup. Add managed template pairs there. Do not add a second independent generation list to sync. Optional GitHub simulation and Woo status workflows are generated only for the GitHub host. Consumer-owned seeds survive pack disablement; reconcile their entrypoint includes manually.

Manifest producers build complete results in private temporary files before publishing them through `scripts/lib/managed_manifest_io.rb`, which retries interrupted and short writes. Callers must check the producer's exit status; process substitutions cannot propagate it. Sync resolves every active, seed and cleanup manifest before changing child files, and update staging stops if any producer fails. The manifest I/O regression suite covers these failure paths and native Bash compatibility.

`scripts/lib/render_template.php` renders PHP constant string literals using PHP serialization, JavaScript/JSON strings using their quote context, and YAML placeholders as quoted scalar values. Configuration is never evaluated as template code. PHP placeholders in executable or interpolated contexts are rejected. Keep new placeholders in supported contexts and extend the generation contract tests when adding a context.

The vendored `lib/wp-plugin-base/plugin-update-checker/` tree is wholly managed and replaced on sync, including removal of retired upstream files. Do not store application code inside that vendor directory. Update staging includes the entire tree so removed files cannot linger in the child commit.
