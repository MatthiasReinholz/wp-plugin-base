# Compatibility

`wp-plugin-base` is backward-compatible by default within a major version for repositories that stay inside the documented contract.

## Stable Public Contract

These surfaces should be treated as public API:

- `.wp-plugin-base.env` keys and semantics
- generated managed files in `.github/`, `.distignore`, and `CONTRIBUTING.md`
- workflow names and their permission contracts
- child-repo branch conventions: `feature/*`, `release/*`, `hotfix/*`
- child-repo semver tags in `x.y.z` format
- foundation release tags in `vX.Y.Z` format
- `PACKAGE_INCLUDE` and `PACKAGE_EXCLUDE` semantics, including repo-relative path preservation
- `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE` as the declared suppressions-file location
- readiness-mode metadata checks for plugin headers and `readme.txt`

Changes to those surfaces should only ship as breaking changes in a new major version.

## Supported Repo Variation Points

The foundation is designed for standard WordPress plugin repos, but it allows a small set of overrides for non-standard layouts:

- custom main plugin file name
- optional version constant
- custom readme path
- optional POT file and project name
- custom package include and exclude lists
- custom suppressions file path
- custom changelog heading
- optional CODEOWNERS generation

## Operational Modes

The foundation also exposes opt-in modes that change how strict the generated workflows are:

- `WORDPRESS_READINESS_ENABLED=true` enables the stricter WordPress metadata and packaging contract for plugin repos that are already ready for release-grade validation.
- `WORDPRESS_QUALITY_PACK_ENABLED=true` enables the broader PHP quality pack as a readiness submode.
- `WORDPRESS_SECURITY_PACK_ENABLED=true` enables the narrower security-focused pack and its public-endpoint scan as a readiness submode.

## Intentional Non-Goals

The foundation does not aim to support arbitrary release conventions. It stays opinionated around:

- `main` as the protected release base branch
- release and hotfix pull requests as the publishing trigger
- WordPress-style changelog sections
- vendored `.wp-plugin-base/` source in the child repo

It also does not define plugin runtime architecture. Any future runtime starter should be additive and should not break the delivery-foundation contract for existing adopters.
