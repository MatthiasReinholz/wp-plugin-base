# Release Model

The shared release model is:

- short-lived `feature/*`, `release/*`, and `hotfix/*` branches
- protected `main`
- `prepare-release` creates or updates `release/x.y.z`
- merging `release/*` or `hotfix/*` into `main` creates the annotated tag and publishes the GitHub release in the same finalize workflow
- `release.yml` remains available as a manual recovery path for an already existing tag
- publish only succeeds for versions that match the merge commit of the correct merged release or hotfix PR
- release workflows attach GitHub artifact attestations for the published ZIP asset

WordPress.org deploy is opt-in and disabled by default.

When you enable WordPress.org deploy, set `WP_ORG_DEPLOY_ENABLED=true` in GitHub Actions settings as either a repository variable or an environment variable.
Store `SVN_USERNAME` and `SVN_PASSWORD` as environment secrets when possible, and protect that environment with reviewers.
