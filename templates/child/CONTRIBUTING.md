# Contributing

This file is managed by `wp-plugin-base`. Update it from the foundation repo instead of hand-editing it here.

## Branching Model

This repository uses short-lived branches:

- `main`: protected and intended to stay releasable
- `feature/<topic>`: normal development work
- `release/<version>`: release preparation only
- `hotfix/<version>`: urgent production fixes branched from `main`

Do not push directly to `main`. Open a change request (PR/MR) instead.

## Release Process

Releases are merge-driven and tag-backed. A branch push must never publish a plugin release.

Normal release flow:

1. Merge the intended feature branches into `main`.
2. Run the managed release-preparation automation and choose `patch`, `minor`, `major`, or `custom`.
   On GitHub this is the `prepare-release` workflow. On GitLab this is the manual `prepare_release` pipeline job.
   Rerunning release preparation for the same version refreshes the existing `release/x.y.z` branch and updates the existing change request if needed.
3. Review the generated `release/x.y.z` change request.
4. Review the auto-generated changelog entry, adjust it if needed, and complete any plugin-specific smoke tests.
5. Merge the `release/x.y.z` change request into `main`.
6. The merged release flow creates the `x.y.z` tag and publishes the platform release from the selected automation host.
7. Use the host-specific release recovery flow only for an existing stable tag if automatic publication needs to be repeated.

Hotfixes use the same model from `hotfix/x.y.z` branches.

## CI And Release Automation

This project uses local managed workflow files generated from `wp-plugin-base` version `__FOUNDATION_VERSION__`.

If you use a coding agent in this repository, treat `.wp-plugin-base/` as authoritative infrastructure code and avoid hand-editing generated managed files directly. Make behavior changes in the vendored foundation source/templates, then rerun sync.

Managed automation files:

- `.github/dependabot.yml`, `.github/CODEOWNERS`, and `.github/workflows/*.yml` when `AUTOMATION_PROVIDER=github`
- `.gitlab-ci.yml` and `.gitlab/CODEOWNERS` when `AUTOMATION_PROVIDER=gitlab`
- `.editorconfig`
- `.gitattributes`
- `.gitignore`
- the managed distignore path (`.distignore` by default, or `DISTIGNORE_FILE`)
- `SECURITY.md`
- `uninstall.php.example`
- `.phpcs.xml.dist`, `phpstan.neon.dist`, and `phpstan.neon` when `WORDPRESS_QUALITY_PACK_ENABLED=true` (full quality pack)
- `phpunit.xml.dist`, `tests/bootstrap.php`, `tests/wp-plugin-base/PluginLoadsTest.php`, `.wp-plugin-base-quality-pack/composer.json`, `.wp-plugin-base-quality-pack/composer.lock`, and `tests/wp-plugin-base/bootstrap-child.php` when either `WORDPRESS_QUALITY_PACK_ENABLED=true` or `PHP_RUNTIME_MATRIX` is set with `PHP_RUNTIME_MATRIX_MODE=strict` (PHPUnit bridge path)
- `.phpcs-security.xml.dist` and `.wp-plugin-base-security-pack/**` when `WORDPRESS_SECURITY_PACK_ENABLED=true`
- `.github/workflows/woocommerce-qit.yml` when `WOOCOMMERCE_QIT_ENABLED=true`
- `docs/rest-operations-pack.md` and `lib/wp-plugin-base/rest-operations/**` when `REST_OPERATIONS_PACK_ENABLED=true`
- `docs/admin-ui-pack.md`, `lib/wp-plugin-base/admin-ui/**`, and `.wp-plugin-base-admin-ui/build.sh` / `.wp-plugin-base-admin-ui/shared/**` when `ADMIN_UI_PACK_ENABLED=true`
- `.wp-plugin-base-security-suppressions.json`, or the path configured by `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE`, when absent

GitHub repos use `finalize-release.yml` as the normal automated publish path, `release.yml` as the manual recovery workflow for an already existing stable tag, and `publish-tag-release.yml` as a prerelease-only safety net for tags such as `v1.2.3-beta.1`. GitLab repos use the managed `.gitlab-ci.yml` release stage for both tagged publication and manual recovery. `.github/dependabot.yml` is GitHub-only and keeps GitHub Actions pins moving through reviewable PRs.
Managed CI also runs a separate `gitleaks` secret-scan job by default.
When `WORDPRESS_QUALITY_PACK_ENABLED=true` or `WORDPRESS_SECURITY_PACK_ENABLED=true`, treat those settings as readiness submodes. Both require `WORDPRESS_READINESS_ENABLED=true`.

Set `RELEASE_READINESS_MODE=security-sensitive` for plugins that should fail closed before release unless readiness, quality, security, strict Plugin Check, and dependency-audit coverage are all enabled without narrowed Plugin Check filters.

When `WORDPRESS_SECURITY_PACK_ENABLED=true`, readiness validation also runs a focused WordPress security pack:

- explicit `WordPress.Security` sniffs for escaping, nonce verification, and sanitized input
- explicit `WordPress.DB` sniffs for direct queries and prepared SQL
- explicit `WordPress.WP.Capabilities` checks
- a REST authorization pattern scan that fails on missing or always-public REST permission callbacks unless explicitly justified
- dependency audits for root `composer.lock` and runtime `package-lock.json` files when present

If `PHP_RUNTIME_MATRIX` is set, CI also runs a lightweight runtime smoke job across the listed PHP versions. That job reruns repository validation, WordPress metadata checks, and a direct main-plugin load smoke with each interpreter version so syntax-, include-, and interpreter-level issues surface before release. Set `PHP_RUNTIME_MATRIX_MODE=strict` to additionally run PHPUnit in the matrix when `phpunit.xml.dist` and the managed quality-pack tool bundle are present, including bridge-only mode when `WORDPRESS_QUALITY_PACK_ENABLED=false`.

When that PHPUnit bridge path is enabled, `tests/bootstrap.php` is managed by foundation sync. Keep child-specific PHPUnit preloads and support-class requires in `tests/wp-plugin-base/bootstrap-child.php`, which is seeded as child-owned.

If `WOOCOMMERCE_QIT_ENABLED=true`, sync also manages a manual `woocommerce-qit` workflow. That workflow is intentionally opt-in, expects WooCommerce QIT access plus `QIT_USER` and `QIT_APP_PASSWORD` secrets, and uses the pinned `woocommerce/qit-cli` version managed by the foundation script.

If this repository does not already have a `CHANGELOG.md`, the first sync also seeds one from the foundation template. After that initial creation, the project owns its changelog content.

The REST operations pack and admin UI pack also seed child-owned files on first enablement. Those seeded files stay project-owned after creation, but validation still expects them to remain present while the pack is enabled.

Before opening or merging changes, run:

```bash
bash .wp-plugin-base/scripts/ci/validate_project.sh
```

That command enforces the generated managed-file surface, not just one host's automation directory.

GitHub projects need the repository setting `Allow GitHub Actions to create and approve pull requests` for `prepare-release` and `update-foundation`.
If managed GitHub update workflows need to push `.github/workflows/*` changes, add the optional repository secret `WP_PLUGIN_BASE_PR_TOKEN`. The managed `update-foundation` and `update-external-dependencies` workflows prefer that token for PR creation and otherwise fall back to `github.token`.

GitLab projects need CI credentials that can push branches and create merge requests. `CI_JOB_TOKEN` is enough for read-only release verification, but long-lived write flows may require a project access token exposed as `GITLAB_TOKEN`.

The WordPress.org deploy path is built in but opt-in. It only runs when `WP_ORG_DEPLOY_ENABLED=true`.

Set `WP_ORG_DEPLOY_ENABLED` in your CI settings as either:

- a repository variable for the whole repository, or
- an environment variable on the deployment environment used by the release workflow

If WordPress.org deploy is enabled, keep `SVN_USERNAME` and `SVN_PASSWORD` in protected CI secrets, and protect the `PRODUCTION_ENVIRONMENT` environment with at least one reviewer. `PRODUCTION_ENVIRONMENT` defaults to `production` when unset. GitHub validation checks that protection automatically. GitLab validation fails closed until you rerun with `WP_PLUGIN_BASE_GITLAB_DEPLOY_ENV_ACKNOWLEDGED=true` after reviewing the environment manually.

Repair release flows verify that the requested tag already exists and skip WordPress.org redeploy by default so a repair run does not mutate an existing SVN tag. GitHub uses the manual `release.yml` workflow for stable repairs and the `publish-tag-release.yml` workflow to create or repair GitHub prereleases from trusted prerelease tags. GitLab uses the tagged `release` job in the managed `.gitlab-ci.yml`. Only set `WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY=true` for an intentional break-glass redeploy of the latest repository release tag.

## Security Expectations

This project inherits the foundation security model:

- workflow action references must stay pinned to full commit SHAs
- the project should keep automation credentials and host-specific CI policies tightly scoped for the pinned foundation version
- workflow, script, and dependency-policy changes should be reviewed like privileged infrastructure changes
- `update-foundation` only trusts published foundation releases that pass provenance checks
