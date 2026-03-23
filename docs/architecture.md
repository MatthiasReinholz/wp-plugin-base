# Architecture

`wp-plugin-base` splits reuse into two layers.

- Reusable workflows live in `.github/workflows/` and are referenced from your project with a pinned foundation tag.
- Shared source files live inside your project under `.wp-plugin-base/` as vendored source.

This avoids runtime dependencies while still allowing upstream improvements to flow into project repositories through update PRs.

Your project repository is always the release source of truth. Packaging, tagging, GitHub release creation, and optional WordPress.org deploy all run from your project repository.
