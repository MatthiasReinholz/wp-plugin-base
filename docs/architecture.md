# Architecture

`wp-plugin-base` splits reuse into two layers.

- Managed local workflows live in your project's `.github/workflows/`.
- Shared source files live inside your project under `.wp-plugin-base/` as vendored source.

This avoids runtime dependencies while still allowing upstream improvements to flow into project repositories through update PRs.

Your project repository is always the release source of truth. Packaging, tagging, GitHub release creation, and optional WordPress.org deploy all run from your project repository.

## Workflow Handling

Workflow handling is intentionally local-first:

- your project keeps managed local workflows in `.github/workflows/`
- those workflows execute directly against your project checkout
- shared shell scripts and templates are read from the vendored `.wp-plugin-base/` directory inside your project
- only the optional foundation self-update workflow reaches back to the `wp-plugin-base` repository

That means day-to-day CI and release automation work without cross-repo reusable workflow access. The main requirement is that `.wp-plugin-base/` is committed in your project.
