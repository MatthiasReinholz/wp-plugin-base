# Compatibility

`wp-plugin-base` is backward-compatible by default within a major version for repositories that stay inside the documented contract.

## Stable Public Contract

These surfaces should be treated as public API:

- `.wp-plugin-base.env` keys and semantics
- generated managed files in `.github/`, root-managed policy files, the configured suppressions file path, and any enabled quality/security/QIT pack files
- workflow names and their permission contracts
- child-repo branch conventions: `feature/*`, `release/*`, `hotfix/*`
- child-repo semver tags in `x.y.z` format
- foundation release tags in `vX.Y.Z` format
- `PACKAGE_INCLUDE` and `PACKAGE_EXCLUDE` semantics, including repo-relative path preservation
- `DISTIGNORE_FILE` as the managed distignore path
- `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE` as the declared suppressions-file location
- `PRODUCTION_ENVIRONMENT` defaulting to `production` when unset
- readiness-mode metadata checks for plugin headers and `readme.txt`
- REST/admin pack enablement keys, managed runtime primitives, and seeded required surfaces when those packs are enabled

Changes to those surfaces should only ship as breaking changes in a new major version.

## Supported Repo Variation Points

The foundation is designed for standard WordPress plugin repos, but it allows a small set of overrides for non-standard layouts:

- custom main plugin file name
- optional version constant
- custom readme path
- optional POT file and project name
- custom package include and exclude lists
- custom distignore path
- custom suppressions file path
- custom changelog heading
- optional CODEOWNERS generation
- opt-in REST namespace override for the managed operations pack

## Operational Modes

The foundation also exposes opt-in modes that change how strict the generated workflows are:

- `WORDPRESS_READINESS_ENABLED=true` enables the stricter WordPress metadata and packaging contract for plugin repos that are already ready for release-grade validation.
- `WORDPRESS_QUALITY_PACK_ENABLED=true` enables the broader PHP quality pack as a readiness submode.
- `WORDPRESS_SECURITY_PACK_ENABLED=true` enables the narrower security-focused pack and its public-endpoint scan as a readiness submode.
- `REST_OPERATIONS_PACK_ENABLED=true` enables the managed REST operations/runtime starter surface.
- `ADMIN_UI_PACK_ENABLED=true` enables the managed admin UI/runtime starter surface.
- `ADMIN_UI_STARTER=basic|dataviews` selects which admin starter the pack seeds; the legacy `ADMIN_UI_EXPERIMENTAL_DATAVIEWS=true` flag remains a compatibility alias for `dataviews`. Because starter files are child-owned and seeded once, switching modes later requires manual reconciliation or intentional re-seeding.
- Disabling the admin UI pack is also a manual reconciliation step: sync removes managed bootstrap files, but child-owned entrypoints, `BUILD_SCRIPT=.wp-plugin-base-admin-ui/build.sh`, and any existing `assets/admin-ui/` outputs must be reconciled by the project before validation or packaging will pass.

## Intentional Non-Goals

The foundation does not aim to support arbitrary release conventions. It stays opinionated around:

- `main` as the protected release base branch
- release and hotfix pull requests as the publishing trigger
- WordPress-style changelog sections
- vendored `.wp-plugin-base/` source in the child repo

It also does not define plugin runtime architecture. Any future runtime starter should be additive and should not break the delivery-foundation contract for existing adopters.
