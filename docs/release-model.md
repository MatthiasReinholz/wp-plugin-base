# Release Model

The shared release model is:

- short-lived `feature/*`, `release/*`, and `hotfix/*` branches
- protected `main`
- `prepare-release` creates or updates `release/x.y.z`
- merging `release/*` or `hotfix/*` into `main` creates the annotated tag, publishes GitHub release artifacts, and runs enabled distribution channels in the same finalize workflow
- `release.yml` remains available as a manual recovery path for an already existing tag, verifies that the tag exists remotely, checks out that exact tag, and uses GitHub release repair mode when the release already exists
- publish only succeeds for versions that match the merge commit of the correct merged release or hotfix PR
- release workflows attach GitHub artifact attestations for the published ZIP asset

## Distribution Channels At Release Time

| Channel | Default | Enablement | Notes |
| --- | --- | --- | --- |
| GitHub tag + GitHub Release | enabled | core flow | authoritative publication point |
| WordPress.org SVN deploy | disabled | `WP_ORG_DEPLOY_ENABLED=true` | post-publish channel step |
| WooCommerce.com Marketplace deploy | disabled | `WOOCOMMERCE_COM_DEPLOY_ENABLED=true` + `WOOCOMMERCE_COM_PRODUCT_ID` | post-publish channel step |

WordPress.org deploy is opt-in and disabled by default.

When you enable WordPress.org deploy, set `WP_ORG_DEPLOY_ENABLED=true` in GitHub Actions settings as either a repository variable or an environment variable.
Store `SVN_USERNAME` and `SVN_PASSWORD` as deployment-environment secrets, and protect that environment with reviewers.

Manual repair runs skip WordPress.org redeploy by default so an existing `plugins.svn.wordpress.org/<slug>/tags/<version>` entry is not silently rewritten. Only set `WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY=true` for an intentional break-glass redeploy of the latest repository release tag.

Release publication is GitHub-first: tag + GitHub release are published first, then enabled channels (WordPress.org and WooCommerce.com) run post-publish.

This can produce a public GitHub release even when a downstream channel fails. That is intentional: channel failures remain visible (workflow ends failed) and are repaired through `release.yml` and `woocommerce-status.yml`.

## Migration Note

For repositories migrating from older behavior where WordPress.org deploy ran before tag publication, this is an intentional behavioral change: WordPress.org channel failures no longer block tag + GitHub release publication.

See:

- [WooCommerce.com distribution](distribution-woocommerce-com.md)
- [GitHub Release updater distribution](distribution-github-release-updater.md)
- [Update model](update-model.md)
- [Troubleshooting](troubleshooting.md)
