# Foundation Release Process

Projects using the foundation update against published foundation releases, not branch heads.

## Release Rules

- Foundation versions use `vX.Y.Z`.
- Each project pins one exact version in `FOUNDATION_VERSION`.
- Automated update PRs only consider published GitHub Releases in the same major series.
- Major upgrades are manual because they may include contract changes.

## Releasing The Foundation

The foundation now uses the same staged release model as the plugin repos.

1. Run `prepare-foundation-release`.
   Rerunning it for the same version refreshes the existing `release/vX.Y.Z` branch and updates the existing PR if needed.
2. Review the generated `release/vX.Y.Z` pull request.
3. Merge the release PR into `main`.
4. `finalize-foundation-release` creates the annotated tag and publishes the GitHub Release in the same workflow.
5. `release-foundation` is only the manual recovery workflow for an already existing tag.

Only after the GitHub Release exists should projects auto-update to that version.

## Recommended Governance

- protect `main`
- require PR review for foundation changes
- keep the release workflow manual
- treat any change to scripts, workflow interfaces, or generated managed files as foundation API surface
