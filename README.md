# wp-plugin-base

`wp-plugin-base` is a GitHub-centric foundation for WordPress plugin repositories.

It is the **delivery and governance layer** for plugin repos:

- managed local GitHub Actions workflows
- release, packaging, and optional WordPress.org deployment automation
- workflow hardening and provenance checks
- vendored scripts, templates, and documentation under `.wp-plugin-base/`

It is **not** a general plugin runtime framework. It does not provide plugin-side DI, PSR-4 runtime scaffolding, settings abstractions, REST controllers, or block architecture. Those concerns should remain outside this repo or move into a future companion runtime layer.

It provides two reuse surfaces:

- managed repository files generated into your project (including `.github/workflows/*` and `.github/dependabot.yml`)
- vendored source under `.wp-plugin-base/` inside your project for scripts, templates, and documentation

The foundation is a development dependency only. The default baseline must never become a runtime dependency of the released plugin ZIP. A small, explicit opt-in runtime pack exists for GitHub Release in-dashboard updates and is disabled by default.

The repository also enforces a tracked-file hygiene policy. Files such as `.DS_Store`, `Thumbs.db`, `Desktop.ini`, editor workspace folders, and transient debug logs are treated as forbidden repository content and fail validation if present.

## Who It Is For

`wp-plugin-base` is optimized first for product teams and maintainers who need:

- repeatable release automation across plugin repositories
- a hardened GitHub Actions policy by default
- a vendored, reviewable infrastructure layer instead of opaque reusable workflows
- a clear update path for shared repo automation

If you only need a minimal plugin starter and do not want shared CI/release governance, `wp scaffold plugin` or a simpler starter is a better fit.

## Feature Matrix

Default behavior is intentionally conservative. Optional channels and packs are opt-in.

| Capability | Type | Default | Enablement Surface |
| --- | --- | --- | --- |
| GitHub Release publication | Layer 1 core | enabled | built into managed release workflows |
| WordPress.org deploy | distribution channel | disabled | GitHub Actions variable `WP_ORG_DEPLOY_ENABLED=true` |
| WooCommerce.com deploy | distribution channel | disabled | GitHub Actions variable `WOOCOMMERCE_COM_DEPLOY_ENABLED=true` + `.wp-plugin-base.env` `WOOCOMMERCE_COM_PRODUCT_ID` |
| GitHub Release updater runtime pack | Layer 2 runtime pack | disabled | `.wp-plugin-base.env` `GITHUB_RELEASE_UPDATER_ENABLED=true` |
| REST operations pack | Layer 2 runtime pack | disabled | `.wp-plugin-base.env` `REST_OPERATIONS_PACK_ENABLED=true` |
| Admin UI pack | Layer 2 runtime pack | disabled | `.wp-plugin-base.env` `ADMIN_UI_PACK_ENABLED=true` |
| WooCommerce QIT workflow pack | optional workflow pack | disabled | `.wp-plugin-base.env` `WOOCOMMERCE_QIT_ENABLED=true` |
| Simulate release workflow | optional workflow pack | disabled | `.wp-plugin-base.env` `SIMULATE_RELEASE_WORKFLOW_ENABLED=true` |

## Quick Start

1. Vendor this repo into your plugin repository at `.wp-plugin-base/`.
2. If this is a blank repo, create the plugin main file and `readme.txt` before you sync.
3. Create `.wp-plugin-base.env` from `.wp-plugin-base/templates/child/.wp-plugin-base.env.example`.
4. Fill in the required values.
5. Run `bash .wp-plugin-base/scripts/update/sync_child_repo.sh`.
6. Run `bash .wp-plugin-base/scripts/ci/validate_project.sh`.
7. Commit `.wp-plugin-base/`, `.wp-plugin-base.env`, and the generated managed files.

For the foundation repo itself, run:

```bash
bash scripts/foundation/validate.sh
bash scripts/foundation/bootstrap_strict_local.sh "$PWD/.wp-plugin-base-tools"
export PATH="$PWD/.wp-plugin-base-tools:$PATH"
bash scripts/foundation/validate.sh --mode strict-local
bash scripts/foundation/validate-full.sh
```

`validate.sh` defaults to `fast-local` mode, which tolerates missing foundation-only lint/security tools and reports reduced assurance explicitly. Use `bash scripts/foundation/validate.sh --mode strict-local` when you want the local run to fail if any required foundation lint/security tool is missing. `validate-full.sh` requires Docker and adds the WordPress readiness and Plugin Check fixtures on top. In CI the full suite skips rerunning the fast suite so the matrix does not pay for the same checks twice.

## Local Tooling Contract

Fast local validation depends on these commands being available:

- `bash`
- `git`
- `php`
- `node`
- `ruby`
- `perl`
- `jq`
- `rsync`
- `zip`
- `unzip`

`rg` is optional. The workflow auditor uses it when available and falls back to `grep` otherwise.

Full local validation and optional flows need additional tools:

- `gh` for GitHub release and pull request automation
- `docker` for WordPress readiness validation, Plugin Check, and the full foundation validation suite
- `python3` for WordPress.org deployment credential handling
- `svn` for WordPress.org deployment
- `wp` is not required locally; release-time POT generation uses the pinned `@wordpress/env` bundle when `POT_FILE` is configured

The shared scripts now fail fast with explicit missing-tool errors instead of failing deeper into release or update flows.

Foundation-only linting uses `shellcheck`, `actionlint`, `yamllint`, `markdownlint-cli2`, `codespell`, `editorconfig-checker`, and `gitleaks` when they are installed locally. Foundation CI installs and runs them strictly even if they are absent on a contributor machine.

On macOS, install the binary tools locally with:

```bash
brew install shellcheck actionlint editorconfig-checker gitleaks
```

Install the local Markdown linting bundle with the committed lockfile:

```bash
npm ci --prefix tools/markdownlint --ignore-scripts --no-audit --no-fund
```

Foundation CI now installs the Node and Python lint toolchains from committed lock files and hash-pinned requirements. `tools/wordpress-env` remains a separate lockfile-backed npm tooling bundle, and shared scripts install it with `npm ci --no-audit --no-fund` from the committed `package-lock.json`.

To bootstrap strict-local foundation validation from a clean clone, use:

```bash
bash scripts/foundation/bootstrap_strict_local.sh "$PWD/.wp-plugin-base-tools"
export PATH="$PWD/.wp-plugin-base-tools:$PATH"
bash scripts/foundation/validate.sh --mode strict-local
```

## Security Model

`wp-plugin-base` assumes a locked-down GitHub Actions posture:

- workflows are local to your project and run against the checked-out repository
- every external action must be pinned to a full commit SHA
- only a small approved action allowlist is permitted
- custom project workflows stay read-only by default; privileged write flows remain managed
- release and update workflows use repo-local shell scripts where practical instead of additional third-party actions
- foundation self-updates only trust published foundation releases that pass provenance checks

See [Security model](docs/security-model.md) for the full policy and the current approved action set.

## Access Requirements

For your project to consume this foundation successfully:

- your project must commit both `.wp-plugin-base/` and `.wp-plugin-base.env` before the shared workflows can run
- if you use the automated foundation self-update workflow, the GitHub Actions runner must be able to read releases from `FOUNDATION_REPOSITORY`
- if you want workflows such as `prepare-release` or `update-foundation` to open pull requests, the repository must allow GitHub Actions to create and approve pull requests
- if foundation or managed dependency updates may change `.github/workflows/*`, set the repository or organization secret `WP_PLUGIN_BASE_PR_TOKEN` to a token that can write contents, pull requests, and workflows

If those conditions are not met, the local project workflows will either fail to find `.wp-plugin-base/` or, for self-update only, fail to reach the foundation release source.

To enable pull request creation in GitHub:

1. Open your repository on GitHub.
2. Go to `Settings` -> `Actions` -> `General`.
3. Scroll to `Workflow permissions`.
4. Select `Read and write permissions`.
5. Enable `Allow GitHub Actions to create and approve pull requests`.
6. Save the changes.

If `Allow GitHub Actions to create and approve pull requests` is greyed out:

1. Open the parent organization on GitHub.
2. Go to `Settings` -> `Actions` -> `General`.
3. Allow repositories in the organization to let GitHub Actions create and approve pull requests.
4. Return to the repository and enable the repository-level setting there if GitHub still requires it.

See [Troubleshooting](docs/troubleshooting.md) for the failure modes and the organization-level case.

## Project Contract

Each project repository should contain:

- `.wp-plugin-base/` populated from this repo as vendored source
- `.wp-plugin-base.env` with project-specific metadata
- plugin-local code and assets
- managed local workflow files in `.github/workflows/`

Managed files are generated from `templates/child/` by running:

```bash
bash .wp-plugin-base/scripts/update/sync_child_repo.sh
```

Validate the repo contract locally with:

```bash
bash .wp-plugin-base/scripts/ci/validate_project.sh
```

That command enforces the generated managed-file surface, not just `.github/workflows/*`. A synced repo must keep the managed root files, the configured suppressions file, and any enabled quality/security/QIT pack files present as regular files.

You can bootstrap `.wp-plugin-base/` with `git subtree` if you want that history locally, but the shared update workflow only requires a normal vendored copy.

If your plugin ships files from nested directories, keep `PACKAGE_INCLUDE`, `PACKAGE_EXCLUDE`, and `DISTIGNORE_FILE` as explicit repo-relative paths. Absolute paths are rejected. The default package excludes repo-root `packages/` and `routes/`, which keeps build-only workspaces out of the install ZIP and translation scan; include those directories explicitly if they are part of the shipped plugin.

The managed `.github/dependabot.yml` file checks for GitHub Actions updates every week. Projects should keep Dependabot enabled so pinned action SHAs keep moving forward through normal review PRs.

Managed child CI also runs a separate `gitleaks` secret-scan job by default. That job installs only the pinned scanner binary, scans the project checkout, and fails the workflow if secrets are detected.

Release publishing now emits three independent trust artifacts:

- GitHub build attestation for the released package
- CycloneDX SBOM for the packaged release contents
- Sigstore keyless bundle for the released blob

Use `bash .wp-plugin-base/scripts/release/verify_sigstore_bundle.sh <owner/repo> <artifact-path> <bundle-path> plugin` for strict consumer verification against the expected release workflows.

The foundation repository also runs an OpenSSF `scorecard` workflow on the default branch and publishes SARIF findings to GitHub code scanning.
It also includes a scheduled external dependency updater workflow at `.github/workflows/update-plugin-check.yml` (display name: `update-external-dependencies`). That workflow checks update candidates, refreshes pinned versions and hashes, and opens reviewable PRs through the same PR-governed update mechanism used by foundation updates. For `WordPress/plugin-check`, updates stay constrained to the current major series, published non-draft/non-prerelease releases, a reviewed release-author allowlist, and a 7-day stabilization window. External dependency PRs include a shared reviewer warning when first-party provenance cannot be verified automatically.

## Recommended GitHub Actions Policy

Apply this policy in GitHub under `Settings` -> `Actions` -> `General` for each project repository or, preferably, at the organization level:

1. Under `Actions permissions`, choose `Allow OWNER, and select non-OWNER, actions and reusable workflows`.
2. Allow GitHub-authored actions.
3. Allow only the specific non-GitHub actions that the current foundation version documents in [Security model](docs/security-model.md).
4. Enable `Require actions to be pinned to a full-length commit SHA`.

This foundation already generates workflows that match that policy. Keeping the GitHub setting aligned means GitHub rejects unexpected workflow drift before a compromised action can run.

## Foundation Release Contract

Foundation releases use semver tags with a `v` prefix such as `v1.0.1`.

- your project pins `FOUNDATION_VERSION` to one exact foundation release
- automated foundation update PRs only consider published GitHub Releases, not arbitrary tags or branch heads
- automatic updates stay within the current major series
- major foundation upgrades are manual

## Coding Agent Conventions

If you are using an AI coding agent (or maintaining this repo as if it were one), treat these as hard invariants:

1. Config key changes:
   - update all four surfaces together: `scripts/lib/load_config.sh`, `docs/config-schema.json`, `README.md` config list, and `templates/child/.wp-plugin-base.env.example`
   - run `bash scripts/ci/validate_config_contract.sh`
2. Managed workflow changes:
   - keep reusable/root workflows and child templates in lockstep
   - run `bash scripts/foundation/test_workflow_parity.sh`
3. Distribution/update channel changes:
   - update workflow logic, docs, security model host allowlist (if network surface changed), and release/update fixtures
   - run `bash scripts/foundation/run_release_update_fixture_checks.sh "$PWD"`
4. Dependency update automation changes:
   - keep `docs/dependency-inventory.json` in sync with `.github/workflows/update-plugin-check.yml` and `scripts/update/prepare_external_dependency_update.sh`
   - run `bash scripts/ci/validate_dependency_inventory.sh` and `bash scripts/foundation/test_dependency_inventory.sh`

For a maintainer-oriented change map, see [Maintainer and agent map](docs/maintainer-agent-map.md).

## Config

Required keys in `.wp-plugin-base.env`:

- `FOUNDATION_REPOSITORY`
- `FOUNDATION_VERSION`
- `PLUGIN_NAME`
- `PLUGIN_SLUG`
- `MAIN_PLUGIN_FILE`
- `README_FILE`
- `ZIP_FILE`
- `PHP_VERSION`
- `NODE_VERSION`

Optional keys:

- `PHP_RUNTIME_MATRIX`
- `PHP_RUNTIME_MATRIX_MODE`
- `VERSION_CONSTANT_NAME`
- `POT_FILE`
- `POT_PROJECT_NAME`
- `WORDPRESS_ORG_SLUG`
- `WORDPRESS_READINESS_ENABLED`
- `WORDPRESS_QUALITY_PACK_ENABLED`
- `WORDPRESS_SECURITY_PACK_ENABLED`
- `WOOCOMMERCE_QIT_ENABLED`
- `WOOCOMMERCE_COM_PRODUCT_ID`
- `WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS`
- `GITHUB_RELEASE_UPDATER_ENABLED`
- `GITHUB_RELEASE_UPDATER_REPO_URL`
- `REST_OPERATIONS_PACK_ENABLED`
- `REST_API_NAMESPACE`
- `REST_ABILITIES_ENABLED`
- `ADMIN_UI_PACK_ENABLED`
- `ADMIN_UI_STARTER`
- `ADMIN_UI_EXPERIMENTAL_DATAVIEWS`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_CHECKS`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_EXCLUDE_CHECKS`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_CATEGORIES`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_IGNORE_CODES`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_STRICT_WARNINGS`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_SEVERITY`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_ERROR_SEVERITY`
- `WP_PLUGIN_BASE_PLUGIN_CHECK_WARNING_SEVERITY`
- `EXTRA_ALLOWED_HOSTS`
- `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE`
- `PACKAGE_INCLUDE`
- `PACKAGE_EXCLUDE`
- `DISTIGNORE_FILE`
- `BUILD_SCRIPT`
- `BUILD_SCRIPT_ARGS`
- `PHPDOC_VERSION_REPLACEMENT_ENABLED`
- `PHPDOC_VERSION_PLACEHOLDER`
- `CHANGELOG_MD_SYNC_ENABLED`
- `CHANGELOG_SOURCE`
- `SIMULATE_RELEASE_WORKFLOW_ENABLED`
- `GLOTPRESS_TRIGGER_ENABLED`
- `GLOTPRESS_URL`
- `GLOTPRESS_PROJECT_SLUG`
- `GLOTPRESS_FAIL_ON_ERROR`
- `DEPLOY_NOTIFICATION_ENABLED`
- `CHANGELOG_HEADING`
- `PRODUCTION_ENVIRONMENT`
- `CODEOWNERS_REVIEWERS`

Use shell-safe `KEY=value` syntax. Quote values that contain spaces, for example `PLUGIN_NAME="Example Plugin"`. `ZIP_FILE` must be a simple `.zip` filename, not a path.

`.wp-plugin-base.env` is a file committed in your project repository. It is not a GitHub Actions variable.

The canonical machine-readable config contract is tracked in [`docs/config-schema.json`](docs/config-schema.json). Foundation validation enforces parity between that schema, `load_config.sh`, this README key list, and `templates/child/.wp-plugin-base.env.example`.

`PACKAGE_INCLUDE`, `PACKAGE_EXCLUDE`, `DISTIGNORE_FILE`, and `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE` must stay repo-relative. `DISTIGNORE_FILE` must point to a `*.distignore` file. `PRODUCTION_ENVIRONMENT` defaults to `production` when unset.

`BUILD_SCRIPT` must be a repo-relative script path. When set, `build_zip.sh` runs it from the repository root before staging files. `BUILD_SCRIPT_ARGS` is an optional comma-separated argument list passed to that script.

`PHPDOC_VERSION_REPLACEMENT_ENABLED=true` enables release-time replacement of `@since <placeholder>` and `@version <placeholder>` in tracked PHP files. Set `PHPDOC_VERSION_PLACEHOLDER` to customize the token (default `NEXT`).

`CHANGELOG_MD_SYNC_ENABLED=true` mirrors generated release notes into `CHANGELOG.md` when the file uses `## x.y.z` or `## vx.y.z` headings. Unknown heading layouts are left untouched.

`CHANGELOG_SOURCE=commits` preserves the existing commit-subject changelog generation. Set `CHANGELOG_SOURCE=prs_titles` to generate notes from merged PR titles using GitHub metadata.

`SIMULATE_RELEASE_WORKFLOW_ENABLED=true` includes an optional managed `simulate-release.yml` workflow for dry-run release previews.

`GLOTPRESS_TRIGGER_ENABLED=true` enables a post-release GlotPress import trigger via `GLOTPRESS_URL` and `GLOTPRESS_PROJECT_SLUG`. `GLOTPRESS_FAIL_ON_ERROR=true` makes trigger failures fail the workflow; default behavior logs a warning and continues.

`DEPLOY_NOTIFICATION_ENABLED=true` enables post-release webhook notifications. The webhook URL must come from `DEPLOY_NOTIFICATION_WEBHOOK_URL` GitHub secret and failures are non-blocking by default.
Because the webhook destination is secret-sourced at runtime, workflow audit host allowlisting cannot statically validate that destination.

Set `CODEOWNERS_REVIEWERS` only if you want the generated project files to include a `.github/CODEOWNERS` file. Use one or more GitHub handles or teams separated by spaces, for example `CODEOWNERS_REVIEWERS="@your-org/platform @your-user"`.

`WORDPRESS_QUALITY_PACK_ENABLED=true` enables the broader PHP quality pack during WordPress readiness validation. It is a readiness submode and therefore requires `WORDPRESS_READINESS_ENABLED=true`.

`WORDPRESS_SECURITY_PACK_ENABLED=true` enables a narrower security-focused pack during WordPress readiness validation. It is a readiness submode and therefore requires `WORDPRESS_READINESS_ENABLED=true`. That pack runs explicit `WordPress.Security`, `WordPress.DB`, and `WordPress.WP.Capabilities` sniffs, blocks risky public endpoint patterns, and audits root Composer/npm runtime dependencies when lock files are present.

Use `.wp-plugin-base-security-suppressions.json` (or set `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE`) to declare intentional public endpoint exceptions with mandatory justification.

If `POT_FILE` is configured, release preparation generates it when it is missing. The path still needs to stay inside the repository and point at a writable location. Translation support also requires a `Domain Path` plugin header, typically `/languages/`, when `POT_FILE` is configured or a `languages/` directory is present.

Workflow files use the `.yml` extension. `.yaml` workflow files are rejected by project and foundation validation.

`WP_PLUGIN_BASE_PLUGIN_CHECK_*` keys provide optional policy controls for Plugin Check execution during WordPress readiness validation:

- `..._CHECKS` runs only specific checks.
- `..._EXCLUDE_CHECKS` excludes specific checks.
- `..._CATEGORIES` filters checks by categories such as `plugin_repo,security`.
- `..._IGNORE_CODES` ignores specific Plugin Check result codes.
- `..._STRICT_WARNINGS=true` fails readiness validation on warnings in addition to errors.
- `..._SEVERITY`, `..._ERROR_SEVERITY`, and `..._WARNING_SEVERITY` pass through severity thresholds to Plugin Check.

`PHP_RUNTIME_MATRIX` enables an additional CI smoke job across the listed interpreter versions, for example `PHP_RUNTIME_MATRIX=8.1,8.2,8.3`. The matrix reruns repository validation and WordPress metadata checks with each configured PHP version. Set `PHP_RUNTIME_MATRIX_MODE=strict` to also run PHPUnit in the matrix when `phpunit.xml.dist` and the managed quality-pack tool bundle are present.

`WOOCOMMERCE_QIT_ENABLED=true` syncs an optional manual WooCommerce QIT workflow into the child repository. That workflow is intended for WooCommerce Marketplace/partner use, expects `QIT_USER` and `QIT_APP_PASSWORD` secrets plus a manually provided WooCommerce extension slug, and uses a pinned internal `woocommerce/qit-cli` version.

`WOOCOMMERCE_COM_PRODUCT_ID` enables WooCommerce.com Marketplace release deploy preflight and upload when the GitHub Actions variable `WOOCOMMERCE_COM_DEPLOY_ENABLED=true` is set. Keep `WOO_COM_USERNAME` and `WOO_COM_APP_PASSWORD` in deployment-environment secrets. Leave the product ID empty during Woo onboarding approval and the workflow soft-skips Woo deploy.

`WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS` controls WooCommerce.com API request timeouts for deploy and status checks (default `30` seconds).

`GITHUB_RELEASE_UPDATER_ENABLED=true` enables an opt-in runtime pack that ships YahnisElsts Plugin Update Checker in `lib/wp-plugin-base/plugin-update-checker/` and a managed bootstrap in `lib/wp-plugin-base/wp-plugin-base-github-updater.php`. Set `GITHUB_RELEASE_UPDATER_REPO_URL=https://github.com/<owner>/<repo>` and add `require_once __DIR__ . '/lib/wp-plugin-base/wp-plugin-base-github-updater.php';` to the plugin main file.

`REST_OPERATIONS_PACK_ENABLED=true` enables an opt-in runtime pack that manages a shared REST operation registry and adapters in `lib/wp-plugin-base/rest-operations/` while seeding child-owned examples in `includes/rest-operations/`. Set `REST_API_NAMESPACE=<plugin-slug>/v1` to override the default namespace and add `require_once __DIR__ . '/lib/wp-plugin-base/rest-operations/bootstrap.php';` to the plugin main file.

`REST_ABILITIES_ENABLED=true` enables the managed Abilities adapter for the REST operations pack when the target WordPress runtime exposes the Abilities API.

Disabling `REST_OPERATIONS_PACK_ENABLED` is also a manual reconciliation step. Sync removes the managed bootstrap, but you must remove the child-owned `require_once __DIR__ . '/lib/wp-plugin-base/rest-operations/bootstrap.php';` include before validation or packaging will pass.

`ADMIN_UI_PACK_ENABLED=true` enables an opt-in runtime pack that manages a shared admin UI bootstrap in `lib/wp-plugin-base/admin-ui/`, seeds child-owned app sources in `.wp-plugin-base-admin-ui/`, and expects `BUILD_SCRIPT=.wp-plugin-base-admin-ui/build.sh`. Add `require_once __DIR__ . '/lib/wp-plugin-base/admin-ui/bootstrap.php';` to the plugin main file. The admin UI pack also requires `REST_OPERATIONS_PACK_ENABLED=true`.

`ADMIN_UI_STARTER=basic|dataviews` selects which admin starter is seeded when the admin UI pack is enabled. `basic` is the default lighter component-only starter. `dataviews` seeds the DataForm/DataViews starter.

`ADMIN_UI_EXPERIMENTAL_DATAVIEWS=true` remains supported as a backward-compatible alias for `ADMIN_UI_STARTER=dataviews`.

The admin starter files are child-owned and seeded once. Changing `ADMIN_UI_STARTER` after the first sync does not rewrite those files; `validate_project.sh` will fail until the child-owned starter is reconciled manually or re-seeded intentionally.

Disabling `ADMIN_UI_PACK_ENABLED` is also a manual reconciliation step. Sync removes the managed bootstrap, but you must remove the child-owned `require_once __DIR__ . '/lib/wp-plugin-base/admin-ui/bootstrap.php';` include, clear `BUILD_SCRIPT=.wp-plugin-base-admin-ui/build.sh`, and delete any stale `assets/admin-ui/` build outputs before validation or packaging will pass. Deleting the seeded `.wp-plugin-base-admin-ui/` sources is optional but recommended once the pack is intentionally removed.

`EXTRA_ALLOWED_HOSTS` allows additional outbound URL hosts for workflow/script audit policy (comma-separated hostnames only). Keep this list minimal.

Local `validate.sh` defaults to `fast-local` mode. That mode still proves the release tooling wiring and SBOM generation, but it reports which checks were skipped when local prerequisites are unavailable. Use `--mode strict-local` for CI-like tool enforcement on a contributor machine. GitHub `foundation-ci` runs `validate.sh --mode ci` and is the authoritative strict execution path for Sigstore/OIDC-sensitive checks.

## WordPress.org Deploy

WordPress.org deploy is built into the shared release workflow and is disabled by default.

To enable it in your project:

1. set `WP_ORG_DEPLOY_ENABLED=true` as either:
   - a GitHub Actions repository variable in the repository settings, or
   - a GitHub Actions environment variable on the selected deployment environment
2. set `WORDPRESS_ORG_SLUG` in `.wp-plugin-base.env`
3. provide `SVN_USERNAME` and `SVN_PASSWORD` as GitHub Actions deployment-environment secrets

If `WP_ORG_DEPLOY_ENABLED` is unset or any value other than `true`, the release workflow skips SVN deploy.

Release publication uses GitHub-first ordering: the annotated tag and GitHub release are published first, then enabled distribution channels (WordPress.org and WooCommerce.com) run post-publish.

WordPress.org can therefore fail after the GitHub release is already public. Use `release.yml` plus `woocommerce-status.yml` as the post-publish channel repair runbook.
If you are migrating from older internal release ordering where WordPress.org deploy blocked tag publication, treat this as a behavior change and update release runbooks.

For stronger review on production publishing, protect the deployment environment named by `PRODUCTION_ENVIRONMENT` and require at least one reviewer before the workflow can access deploy credentials. CI and release readiness checks now fail when WordPress.org deploy is enabled and reviewer protection cannot be verified.

The manual `release.yml` workflow is a recovery path for an already existing Git tag. It verifies that the tag exists remotely, checks out that exact tag, and skips WordPress.org redeploy by default so an existing `tags/<version>` entry is not mutated during a repair run. Only set the repository or environment variable `WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY=true` for an intentional break-glass redeploy of the latest repository release tag.

## Guides

Start here by intent:

- new plugin repository: [New project setup](docs/new-project.md)
- existing plugin migration: [Existing project migration](docs/existing-project-migration.md)
- release and distribution behavior: [Release model](docs/release-model.md)
- security and workflow policy: [Security model](docs/security-model.md)
- maintainer/coding-agent change map: [Maintainer and agent map](docs/maintainer-agent-map.md)

- [New project setup](docs/new-project.md)
- [Existing project migration](docs/existing-project-migration.md)
- [Product layers](docs/layers.md)
- [Release model](docs/release-model.md)
- [WooCommerce.com distribution](docs/distribution-woocommerce-com.md)
- [GitHub Release updater distribution](docs/distribution-github-release-updater.md)
- [Security model](docs/security-model.md)
- [Secure plugin coding contract](docs/secure-plugin-coding-contract.md)
- [Compatibility and public contract](docs/compatibility.md)
- [Foundation release process](docs/foundation-release-process.md)
- [Changelog policy](docs/changelog-policy.md)
- [PR-based changelog notes](docs/pr-changelog.md)
- [Update model](docs/update-model.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Maintainer and agent map](docs/maintainer-agent-map.md)
