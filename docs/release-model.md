# Release Model

The shared release model is:

- short-lived `feature/*`, `release/*`, and `hotfix/*` branches
- protected `main`
- `prepare-release` creates or updates `release/x.y.z`
- merging `release/*` or `hotfix/*` into `main` publishes from the selected downstream host
- GitHub uses the managed finalize workflow to create the annotated tag and publish release artifacts automatically
- GitHub stable tags are owned by the release PR/finalize flow; the managed `publish-tag-release.yml` workflow only publishes trusted prerelease tags such as `v1.2.3-beta.1`
- GitLab uses a managed release MR plus a manual tag push after merge to trigger the tag pipeline and publish release artifacts
- the repair flow verifies that the tag exists remotely, checks out that exact tag, and repairs the host release when it already exists
- publish only succeeds for versions that match the merge commit of the correct merged release or hotfix PR
- release workflows attach the available release evidence for the selected host

## Distribution Channels At Release Time

| Channel | Default | Enablement | Notes |
| --- | --- | --- | --- |
| Selected Git host tag + release | enabled | core flow | authoritative publication point |
| WordPress.org SVN deploy | disabled | `WP_ORG_DEPLOY_ENABLED=true` | post-publish channel step |
| WooCommerce.com Marketplace deploy | disabled | `WOOCOMMERCE_COM_DEPLOY_ENABLED=true` + `WOOCOMMERCE_COM_PRODUCT_ID` | post-publish channel step |

WordPress.org deploy is opt-in and disabled by default.

When you enable WordPress.org deploy, set `WP_ORG_DEPLOY_ENABLED=true` in the selected CI host and store `SVN_USERNAME`/`SVN_PASSWORD` as protected deployment secrets. Protect the deployment environment with reviewers on that host.

Manual repair runs skip WordPress.org redeploy by default so an existing `plugins.svn.wordpress.org/<slug>/tags/<version>` entry is not silently rewritten. Only set `WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY=true` for an intentional break-glass redeploy of the latest repository release tag.

Release publication is host-release-first: the selected Git host release publishes first, then enabled channels (WordPress.org and WooCommerce.com) run post-publish.

This can produce a public Git host release even when a downstream channel fails. That is intentional: channel failures remain visible and are repaired through the selected host's repair path.

External automation/downstream consumers such as `wp-core-base` should consume that authoritative Git host release surface, whether or not the plugin also enables the optional runtime updater pack. The runtime updater is an end-user wp-admin channel, not the managed downstream automation contract.

## Repair Entry Points

| Host path | Trigger | Required input | Expected behavior | Post-repair checks |
| --- | --- | --- | --- | --- |
| GitHub stable release | Manual `release.yml` workflow | existing stable tag such as `1.2.3` | verifies the tag comes from the merged release/hotfix PR, replaces missing release assets, clears draft state after assets exist, and skips WordPress.org redeploy unless `WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY=true` | verify the GitHub Release assets; run `woocommerce-status.yml` when WooCommerce.com is enabled |
| GitHub prerelease | trusted prerelease tag push or rerun | prerelease tag such as `1.2.3-beta.1` | publishes or repairs only prerelease GitHub Releases with ZIP, SBOM, and Sigstore assets; never marks prereleases latest | verify the release is not draft, is marked prerelease, and has non-empty ZIP/SBOM/Sigstore assets |
| GitLab | tagged `release` job in the managed `.gitlab-ci.yml` | existing tag | repairs the selected GitLab release path and skips WordPress.org redeploy unless explicitly allowed | inspect GitLab release assets and Woo vendor/QIT status directly; GitLab has no separate WooCommerce status workflow |

## Migration Note

For repositories migrating from older behavior where WordPress.org deploy ran before tag publication, this is an intentional behavioral change: WordPress.org channel failures no longer block tag + host-release publication.

See:

- [WooCommerce.com distribution](distribution-woocommerce-com.md)
- [Runtime In-Dashboard Updater](distribution-runtime-updater.md)
- [Update model](update-model.md)
- [Troubleshooting](troubleshooting.md)
