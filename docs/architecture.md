# Architecture

`wp-plugin-base` splits reuse into two layers.

- Reusable workflows live in `.github/workflows/` and are referenced from child repos with a pinned foundation tag.
- Shared source files live inside the child repo under `.wp-plugin-base/` as vendored source.

This avoids runtime dependencies while still allowing upstream improvements to flow into child repos through update PRs.

The child repo is always the release source of truth. Packaging, tagging, GitHub release creation, and optional WordPress.org deploy all run from the child repo.
