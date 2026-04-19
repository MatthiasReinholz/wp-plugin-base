# Architecture

`wp-plugin-base` splits reuse into two layers.

- Managed local workflows live in your project's `.github/workflows/`.
- Shared source files live inside your project under `.wp-plugin-base/` as vendored source.

This avoids runtime dependencies while still allowing upstream improvements to flow into project repositories through update PRs.

Your project repository is always the release source of truth. Packaging, tagging, Git host release creation, and optional WordPress.org deploy all run from your project repository.

## Workflow Handling

Workflow handling is intentionally local-first:

- your project keeps managed local workflows in `.github/workflows/`
- those workflows execute directly against your project checkout
- shared shell scripts and templates are read from the vendored `.wp-plugin-base/` directory inside your project
- only the optional foundation self-update workflow reaches back to the `wp-plugin-base` repository

That means day-to-day CI and release automation work without cross-repo reusable workflow access. The main requirement is that `.wp-plugin-base/` is committed in your project.

## Security Handling

The local-first design also narrows the supply-chain surface:

- workflow logic is visible in your project repository
- shared shell logic is vendored and reviewable under `.wp-plugin-base/`
- only a small set of external GitHub Actions remain, all pinned to commit SHAs
- release PR creation, Git host release publication, and WordPress.org deployment are handled by repo-local scripts instead of additional marketplace actions

The only workflow that reaches back to GitHub for foundation content is `update-foundation`, and that path verifies release provenance before it proposes an update.

## Read Next

- [Product layers](layers.md) for Layer 1/Layer 2 boundaries
- [Release model](release-model.md) for publish and channel ordering
- [Update model](update-model.md) for foundation and dependency updater mechanics
- [Security model](security-model.md) for workflow policy and trust controls
