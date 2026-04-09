# Update Model

Your project should keep a vendored copy of `wp-plugin-base` in `.wp-plugin-base/`.

The scheduled `update-foundation` workflow:

- reads `FOUNDATION_VERSION`
- checks for a newer compatible published foundation release in the same major series
- verifies the candidate release provenance by checking the published release metadata asset, its Sigstore bundle, and the tag commit's relationship to `main`
- refreshes the vendored `.wp-plugin-base/` directory from the exact verified commit SHA instead of trusting the mutable tag name twice
- regenerates managed files from templates
- opens a pull request

Major-version updates are intentionally manual.

For external GitHub dependencies that do not have first-party provenance the framework can verify automatically, automated update PRs are still allowed, but they must use the shared external-dependency PR-body helper so reviewers get a standardized warning to verify the upstream release manually before merge.

Dependency trust tiers are tracked in [`docs/dependency-inventory.json`](dependency-inventory.json):

- `verified-provenance` for assets the framework can verify cryptographically end-to-end
- `metadata-only` for external dependencies selected from reviewed release metadata
- `lockfile-backed` for dependencies updated through committed lockfiles and Dependabot
- `manual` for pinned versions that currently require maintainer review and bump commits

`scripts/ci/validate_dependency_inventory.sh` enforces that the inventory, lockfiles, pin patterns, and Dependabot coverage stay in sync.
