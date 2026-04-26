# Foundation Release Process

Projects using the foundation update against published foundation releases, not branch heads.

## Release Rules

- Foundation versions use `vX.Y.Z`.
- Each project pins one exact version in `FOUNDATION_VERSION`.
- Automated update PRs only consider published releases from the configured authoritative source (`github-release` or `gitlab-release`) in the same major series.
- Major upgrades are manual because they may include contract changes.

## Releasing The Foundation

The foundation now uses the same staged release model as the plugin repos.

1. Run `prepare-foundation-release`.
2. Review the generated `release/vX.Y.Z` pull request.
3. Merge the release PR into `main`.
4. `finalize-foundation-release` creates the annotated tag, deploys any required release artifacts, pushes the tag, and then publishes the GitHub Release in the same workflow.
5. The finalize workflow also uploads a signed release-metadata asset and GitHub build attestation for update provenance checks.
6. `release-foundation` is only the manual recovery workflow for an already existing tag and uses release repair mode when a GitHub Release already exists.
7. Foundation update verification consumes the published `dist-foundation-release.json` metadata asset and its Sigstore bundle before any vendored code is refreshed.
8. Review the generated changelog entry before merge and expand it when the default notes are too thin for downstream consumers.

For plugin repositories that set `POT_FILE`, release preparation also regenerates the translation template before the release PR is opened.

Only after the authoritative host release exists should projects auto-update to that version.

## Recommended Governance

- protect `main`
- require PR review for foundation changes
- require review on workflow, script, and dependency-policy paths via CODEOWNERS
- keep the release workflow manual
- treat any change to scripts, workflow interfaces, or generated managed files as foundation API surface
