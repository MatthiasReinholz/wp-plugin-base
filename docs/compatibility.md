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

Changes to those surfaces should only ship as breaking changes in a new major version.

## Supported Repo Variation Points

The foundation is designed for standard WordPress plugin repos, but it allows a small set of overrides for non-standard layouts:

- custom main plugin file name
- optional version constant
- custom readme path
- optional POT file and project name
- custom package include and exclude lists
- custom changelog heading
- optional CODEOWNERS generation

## Intentional Non-Goals

The foundation does not aim to support arbitrary release conventions. It stays opinionated around:

- `main` as the protected release base branch
- release and hotfix pull requests as the publishing trigger
- WordPress-style changelog sections
- vendored `.wp-plugin-base/` source in the child repo

It also does not define plugin runtime architecture. Any future runtime starter should be additive and should not break the delivery-foundation contract for existing adopters.
