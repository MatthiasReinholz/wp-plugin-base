# Release Model

The shared release model is:

- short-lived `feature/*`, `release/*`, and `hotfix/*` branches
- protected `main`
- `prepare-release` creates or updates `release/x.y.z`
- merging `release/*` or `hotfix/*` into `main` creates the annotated tag, deploys to WordPress.org if enabled, pushes the tag, and then publishes the GitHub release in the same finalize workflow
- `release.yml` remains available as a manual recovery path for an already existing tag, verifies that the tag exists remotely, checks out that exact tag, and uses GitHub release repair mode when the release already exists
- publish only succeeds for versions that match the merge commit of the correct merged release or hotfix PR
- release workflows attach GitHub artifact attestations for the published ZIP asset

WordPress.org deploy is opt-in and disabled by default.

When you enable WordPress.org deploy, set `WP_ORG_DEPLOY_ENABLED=true` in GitHub Actions settings as either a repository variable or an environment variable.
Store `SVN_USERNAME` and `SVN_PASSWORD` as deployment-environment secrets, and protect that environment with reviewers.

Manual repair runs skip WordPress.org redeploy by default so an existing `plugins.svn.wordpress.org/<slug>/tags/<version>` entry is not silently rewritten. Only set `WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY=true` for an intentional break-glass redeploy of the latest repository release tag.
