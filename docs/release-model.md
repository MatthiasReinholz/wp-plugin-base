# Release Model

The shared release model is:

- short-lived `feature/*`, `release/*`, and `hotfix/*` branches
- protected downstream `DEFAULT_BRANCH` (`main` by default)
- `prepare-release` creates or updates `release/x.y.z`
- merging `release/*` or `hotfix/*` into the configured default branch publishes from the selected downstream host
- GitHub uses the managed finalize workflow to create the annotated tag and publish release artifacts automatically
- GitHub stable tags are owned by the release PR/finalize flow; the managed `publish-tag-release.yml` workflow only publishes trusted prerelease tags such as `v1.2.3-beta.1`
- GitLab uses a managed release MR plus a manual tag push after merge to trigger the tag pipeline and publish release artifacts
- the repair flow verifies the exact existing tag and its merged release provenance; channel retries reuse the signed published package, while explicit host repair reconstructs missing evidence
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

GitHub manual repair skips WordPress.org deployment unless `WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY=true` is set. GitLab tag jobs deploy enabled channels on first publication and retry them on later runs; matching SVN tags remain unchanged. On either host, replacing different existing SVN tag contents requires the explicit break-glass flag.

SVN tag equality compares file bytes, directory entries and symlink targets;
checkout timestamps are not release content. Synchronization uses checksums,
and status, staging or comparison errors stop publication. Local repository
acceptance tests exercise additions, deletions, immutable retries and failures
without publishing to a live distribution channel.

Publication uses one repository-wide concurrency group on GitHub and one resource group on GitLab. GitHub latest promotion checks all published stable versions; repairing a historical release never promotes it. GitLab refuses a new historical publication after a newer stable release. WordPress.org independently compares repository and SVN tag versions before changing trunk, regardless of the repair flag. A historical host-asset repair remains possible, but promoting an older distribution version is not supported.

All GitHub publishing entry points use the same immutable-payload guard, including reusable recovery and prerelease workflows. An existing plugin ZIP or foundation metadata payload must remain byte-identical during evidence repair. A failed release creation never falls back to overwriting an existing release.

Release publication is host-release-first: the selected Git host release publishes first, then enabled channels (WordPress.org and WooCommerce.com) run post-publish.

This can produce a public Git host release even when a downstream channel fails. That is intentional: channel failures remain visible and are repaired through the selected host's repair path.

External automation/downstream consumers such as `wp-core-base` should consume that authoritative Git host release surface, whether or not the plugin also enables the optional runtime updater pack. The runtime updater is an end-user wp-admin channel, not the managed downstream automation contract.

## Repair Entry Points

| Host path | Trigger | Required input | Expected behavior | Post-repair checks |
| --- | --- | --- | --- | --- |
| GitHub stable release | Manual `release.yml` workflow | existing stable tag such as `1.2.3` | verifies merged-release provenance and downloads the signed published artifacts for channel retry; `repair_host_assets=true` explicitly repairs host evidence, preserving any existing ZIP bytes; WordPress.org requires `WP_PLUGIN_BASE_ALLOW_WPORG_TAG_REDEPLOY=true` | verify the GitHub Release assets; run `woocommerce-status.yml` when WooCommerce.com is enabled |
| GitHub prerelease | trusted prerelease tag push or rerun | prerelease tag such as `1.2.3-beta.1` | publishes or repairs only prerelease GitHub Releases with ZIP, SBOM, and Sigstore assets; never marks prereleases latest | verify the release is not draft, is marked prerelease, and has non-empty ZIP/SBOM/Sigstore assets |
| GitLab | tagged `release` job in the managed `.gitlab-ci.yml` | existing tag | first publication uploads all assets before exposing the release; reruns restore verified published bytes and retry enabled channels; different SVN tag contents require explicit permission | inspect GitLab release assets and Woo vendor/QIT status directly; GitLab has no separate WooCommerce status workflow |

Start manual GitHub stable recovery from the configured default branch. Its workflow copies current protected release helpers outside the historical checkout, then operates on the selected tag payload. Stable signing verifies the certificate identity before publication. Rerunning a historical Actions run still uses that run's old workflow definition; it does not acquire these new controls. Use a new recovery run from the current protected default branch instead.

The stable plugin signature policy accepts this repository's `release.yml` or `finalize-release.yml` on its exact configured `DEFAULT_BRANCH`. Foundation signatures independently retain their protected `main` policy. Same-repository reusable calls from the configured branch preserve that contract. Cross-repository reusable signing has a different identity because [Fulcio uses the called workflow's `job_workflow_ref`](https://github.com/sigstore/fulcio/blob/main/docs/oidc.md); the default policy rejects it before publication. Use the managed child workflows for the supported downstream release path. Broadening signer trust requires an explicit reviewed policy and host acceptance; it is not inferred from the caller repository.

See [downstream branch migration](downstream-branches.md) for historical retry and exact signing-identity rules. Packaging, SBOM generation, signing, upload, and deployment consume one captured [verified package generation](package-lifecycle.md).

## GitLab Acceptance And Credentials

GitLab.com signing uses `SIGSTORE_ID_TOKEN` with audience `sigstore`, declared directly in the project pipeline. Verification binds the exact project, the double slash before `.gitlab-ci.yml`, and `refs/tags/<version>`. Branch identities and signatures for other tags are rejected. See [GitLab signing documentation](https://docs.gitlab.com/ci/yaml/signing_examples/).

Use a protected, masked project access token in `GITLAB_TOKEN` with the API and repository permissions required by release preparation/publication. `CI_JOB_TOKEN` is accepted by adapters where the endpoint and project allow it; it is not a substitute for verifying endpoint permissions. GitLab consumers of a GitHub foundation also need a protected `GH_TOKEN` with read access to that foundation, including its release assets. Tokens remain in environment variables or temporary files, never Git remotes or process arguments in the release adapters.

The local acceptance suite exercises publication ordering, immutable retry behavior, signature identity, token handling, and negative provider responses. A full lifecycle on an actual GitLab runner has not been validated by that suite. Treat GitLab as requiring project-specific acceptance: protected tag creation, OIDC signing and verification, atomic host publication, both enabled channels, and foundation update. Self-managed GitLab signing requires separately configured Sigstore infrastructure and is not established by GitLab.com fixture coverage.

## Migration Note

For repositories migrating from older behavior where WordPress.org deploy ran before tag publication, this is an intentional behavioral change: WordPress.org channel failures no longer block tag + host-release publication.

See:

- [WooCommerce.com distribution](distribution-woocommerce-com.md)
- [Runtime In-Dashboard Updater](distribution-runtime-updater.md)
- [Update model](update-model.md)
- [Troubleshooting](troubleshooting.md)
