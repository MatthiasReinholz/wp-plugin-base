# Update Model

Your project should keep a vendored copy of `wp-plugin-base` in `.wp-plugin-base/`.

The scheduled `update-foundation` workflow:

- reads `FOUNDATION_VERSION`
- checks for a newer compatible published foundation release in the same major series
- verifies the candidate release provenance by checking the published release metadata asset, its Sigstore bundle, and the tag commit's relationship to `main`
- refreshes the vendored `.wp-plugin-base/` directory from the exact verified commit SHA instead of trusting the mutable tag name twice
- regenerates managed files from templates
- opens a pull request

When the regenerated managed files include `.github/workflows/*`, GitHub will reject a branch push authenticated only with the default Actions app token. Repositories that want fully automated workflow-file updates should configure the repository or organization secret `WP_PLUGIN_BASE_PR_TOKEN` with a token that can write contents, pull requests, and workflows. The managed updater workflows prefer that secret automatically when it is present.

Existing child repositories on older foundation versions may still need a one-time manual bootstrap edit to their local `update-foundation.yml` workflow so it passes `WP_PLUGIN_BASE_PR_TOKEN` through before the first workflow-changing foundation update can land automatically.

Major-version updates are intentionally manual.

For external GitHub dependencies that do not have first-party provenance the framework can verify automatically, automated update PRs are still allowed, but they must use the shared external-dependency PR-body helper so reviewers get a standardized warning to verify the upstream release manually before merge.

The foundation repository runs a single scheduled updater workflow for external dependency pins:

- workflow file: `.github/workflows/update-plugin-check.yml`
- workflow display name in Actions UI: `update-external-dependencies`

It applies the same PR-based governance model used by `update-foundation`: detect update candidates, refresh managed pins, validate, and open reviewable PRs.

## External Dependency Coverage

Current dependency handlers in `scripts/update/prepare_external_dependency_update.sh`:

- `plugin-update-checker-runtime`
- `plugin-check`
- `composer-docker-image`
- `shellcheck-binary`
- `actionlint-binary`
- `editorconfig-checker-binary`
- `gitleaks-binary`
- `syft-binary`
- `cosign-binary`

Each handler is responsible for:

1. selecting a candidate update (version or digest)
2. updating the authoritative pin/hash files
3. preparing a standardized external-dependency PR body
4. returning explicit staged paths (`GIT_ADD_PATHS`) for safe commits

Dependency trust tiers are tracked in [`docs/dependency-inventory.json`](dependency-inventory.json):

- `verified-provenance` for assets the framework can verify cryptographically end-to-end
- `metadata-only` for external dependencies selected from reviewed release metadata
- `lockfile-backed` for dependencies updated through committed lockfiles and Dependabot
- `manual` for pinned versions that currently require maintainer review and bump commits

`scripts/ci/validate_dependency_inventory.sh` enforces that the inventory, lockfiles, pin patterns, and Dependabot coverage stay in sync.

## Adding A New External Dependency Handler

When adding a new updater target:

1. implement a new `dependency_id` branch in `scripts/update/prepare_external_dependency_update.sh`
2. add the same `dependency_id` to `.github/workflows/update-plugin-check.yml` matrix
3. update `docs/dependency-inventory.json` with `update.kind: workflow` and `update.path: .github/workflows/update-plugin-check.yml`
4. update any host allowlist requirements in `scripts/ci/audit_workflows.sh` and `docs/security-model.md` if the new handler needs new outbound hosts
5. run:
   - `bash scripts/ci/validate_dependency_inventory.sh`
   - `bash scripts/foundation/test_dependency_inventory.sh`
   - `bash scripts/ci/audit_workflows.sh`
