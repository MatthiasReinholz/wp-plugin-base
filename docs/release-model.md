# Release Model

The shared release model is:

- short-lived `feature/*`, `release/*`, and `hotfix/*` branches
- protected `main`
- `prepare-release` creates or updates `release/x.y.z`
- merging `release/*` or `hotfix/*` into `main` creates the annotated tag automatically
- pushing the tag runs the publish workflow
- publish only succeeds for tags that match the merge commit of the correct merged release or hotfix PR

WordPress.org deploy is opt-in and disabled by default.
