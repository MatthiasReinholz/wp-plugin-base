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
- `.distignore`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `uninstall.php.example`
- `.phpcs.xml.dist` and `.wp-plugin-base-quality-pack/**` when `WORDPRESS_QUALITY_PACK_ENABLED=true`
- `.phpcs-security.xml.dist` and `.wp-plugin-base-security-pack/**` when `WORDPRESS_SECURITY_PACK_ENABLED=true`
- `.github/workflows/woocommerce-qit.yml` when `WOOCOMMERCE_QIT_ENABLED=true`
- `.wp-plugin-base-security-suppressions.json`, or the path configured by `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE`, when absent

Do not hand-edit those files in your project unless you are intentionally diverging from the foundation. If you need a permanent change, make it in `wp-plugin-base` and resync.

`finalize-release.yml` is the standard automated publish path. `release.yml` is the manual recovery workflow for an already existing tag. `.github/dependabot.yml` keeps GitHub Actions pins moving through reviewable PRs. `.github/CODEOWNERS` is optional so projects can choose whether workflow, script, and dependency-file changes require explicit reviewer ownership.

If a project does not already have a `CHANGELOG.md`, sync also seeds one from the child template. After that initial creation, the project owns its changelog content.

`.distignore` excludes repo-root `packages/` and `routes/` by default so build-only workspaces stay out of the install ZIP and translation scan. If either directory belongs in the shipped plugin, add it explicitly through `PACKAGE_INCLUDE` and remove only the paths that should stay excluded through `PACKAGE_EXCLUDE`.

If a project does not already have the configured suppressions file, sync seeds it with an empty suppression set. After that initial creation, the project owns suppression entries and justifications.
