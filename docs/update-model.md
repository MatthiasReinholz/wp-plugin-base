# Update Model

Your project should keep a vendored copy of `wp-plugin-base` in `.wp-plugin-base/`.

The scheduled `update-foundation` automation:

- reads `FOUNDATION_VERSION`
- resolves the authoritative foundation release source from `FOUNDATION_RELEASE_SOURCE_PROVIDER`, `FOUNDATION_RELEASE_SOURCE_REFERENCE`, and `FOUNDATION_RELEASE_SOURCE_API_BASE`
- checks for a newer compatible published foundation release in the same major series
- verifies the candidate release provenance by checking the published release metadata asset, its Sigstore bundle, and the tag commit's relationship to `main`
- installs release security tooling (`cosign`, `syft`, companion binaries) before provenance verification so scheduled/manual updates do not depend on runner preinstalls
- refreshes the vendored `.wp-plugin-base/` directory from the exact verified commit SHA instead of trusting the mutable tag name twice
- regenerates managed files from templates
- opens a reviewable change request on the selected automation host

This flow consumes the authoritative foundation release source only. Optional runtime updater settings such as `PLUGIN_RUNTIME_UPDATE_PROVIDER` do not change which release surface managed automation uses.

Major-version updates are intentionally manual. Both the reusable and generated
child updater read the project runtime configuration and explicitly set up its
PHP and Node.js versions before regeneration and validation.

If you run `scripts/update/verify_foundation_release.sh` directly (outside the managed workflow), ensure `cosign` is already on `PATH` or bootstrap with `scripts/release/install_release_security_tools.sh` first.

For external GitHub dependencies that do not have first-party provenance the framework can verify automatically, automated update PRs are still allowed, but they must use the shared external-dependency PR-body helper so reviewers get a standardized warning to verify the upstream release manually before merge.

The foundation repository runs a single scheduled updater workflow for external dependency pins:

- workflow file: `.github/workflows/update-plugin-check.yml`
- workflow display name in Actions UI: `update-external-dependencies`

It applies the same PR-based governance model used by `update-foundation`: detect update candidates, refresh managed pins, validate, and open reviewable PRs.

For GitHub-hosted repos, managed update workflows prefer an optional repository secret named `WP_PLUGIN_BASE_PR_TOKEN` when they need to push or open a PR that includes `.github/workflows/*` changes. If that secret is absent, they fall back to `github.token`.

## Node.js Runtime Support

New projects default to `NODE_VERSION=24`. Node.js 22 remains supported. Projects
own `.wp-plugin-base.env`, a foundation update changes only `FOUNDATION_VERSION`
in it, and a project can move to Node.js 24 before or after any foundation update.

The managed WordPress environment tooling (`@wordpress/env`, used by Plugin Check,
POT generation and the runtime smoke tests) runs the Docker runtime, which
supports Node.js 22.12.0 or newer. `@wordpress/env` 11.17 also installs its
Playground runtime, whose `@php-wasm/*` packages declare Node.js 24.18.0 or newer.
That runtime is loaded only for `wp-env --runtime=playground`, which the
foundation never uses. The tool's `.npmrc` therefore sets `engine-strict=false`,
and the installer runs `scripts/lib/check_wordpress_env_engines.cjs` before
activating the tool. It enforces the tool manifest's Node.js and npm engines and
the Node.js engines of every package the Docker runtime can load, so a dependency
update that raises that floor fails installation and names the packages.
Foundation CI starts, uses and cleans up real Docker environments on Node.js 22
(the WordPress 6.9 runtime job) and Node.js 24, and runs Plugin Check and POT
generation on Node.js 24.

When moving a project to Node.js 24, prefer the major version so CI resolves the
current security release. Also align project-owned runtime selections, such as
custom workflows, `.nvmrc` files and package `engines`, and on GitLab provision
runtime images with the same version (see
[automation hosts](automation-hosts.md#gitlab-runtime-contract)). The child-owned
admin UI manifests keep `^22.22.2 || ^24.15.0 || >=26.0.0`; no starter change is
required.

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
3. add its exact writable surfaces to `paths_for` in `scripts/update/external_dependency_candidate.py`; publication scripts and their dependencies must never be writable candidate surfaces
4. update `docs/dependency-inventory.json` with `update.kind: workflow` and `update.path: .github/workflows/update-plugin-check.yml`
5. update any host allowlist requirements in `scripts/ci/audit_workflows.sh` and `docs/security-model.md` if the new handler needs new outbound hosts
6. add a handler fixture in `scripts/foundation/test_external_dependency_updates.py`, then run:
   - `bash scripts/foundation/test_external_dependency_updates.sh`
   - `bash scripts/ci/validate_dependency_inventory.sh`
   - `bash scripts/foundation/test_dependency_inventory.sh`
   - `bash scripts/ci/audit_workflows.sh`

## Action pin ownership and migrations

`scripts/lib/action-pins.json` is the authoritative action catalog used by both the
workflow auditor and the sync-time migration. Each entry records the current approved
commit and explicitly reviewed predecessor commits. Keep the documented pins in
[the security model](security-model.md) synchronized; the foundation gate checks
them against the catalog. Sync changes only parsed `uses`
values in child workflows and composite actions; it preserves comments, formatting,
step inputs, scripts, and unrelated text. It upgrades reviewed predecessors to the
current pin and keeps any other full-SHA pin, so a project's own newer pin is never
downgraded. Tags fail closed. The foundation's own audit accepts only current pins;
project validation accepts every full-SHA pin and lists those that differ from the
catalog.

Managed automation stays foundation-owned except for its action pins. The ownership
receipt records each managed file's exact digest and a pin-neutral digest, so project
validation accepts a managed file whose only change is a full-SHA pin, such as a
Dependabot update. On sync, the new generation is rendered and the project's pins
for actions the catalog has not reviewed are reapplied; reviewed predecessors take
the newly rendered pin. Receipts written before pin-neutral digests are matched by
substituting the catalog's reviewed pins. Any other edit to a managed file still
fails validation and sync.

Current updater scripts and both GitHub workflow variants capture migrated paths in a
temporary manifest and stage those reviewed child-owned files alongside managed output.
Older updater workflows cannot gain new staging steps while already running: the first
upgrade from an older foundation can migrate a custom workflow locally but omit it from
the proposed commit. Perform that upgrade manually, run sync and validation, and include
all reported migrated workflow/action paths in the reviewed commit. Subsequent updates
use the new manifest-aware staging flow. Never publish an incomplete update that leaves
custom workflows on rejected predecessor pins.

From v1.10.11, child Dependabot configuration rendered from v1.10.10 and later
templates ignores no actions, so version and security updates reach every
workflow, managed ones included. Earlier templates ignored catalog action
repositories and still render those bytes during ownership recovery. See
[who updates which dependency](dependency-maintenance.md#who-updates-which-dependency). With `DEPENDABOT_ECOSYSTEMS=auto`, the generated child configuration also tracks
root Composer dependencies when `composer.json` exists, npm dependencies at `/`
when a root `package.json` exists, and at `/.wp-plugin-base-admin-ui` when that
package exists or the admin UI pack is enabled. Each generated npm entry groups
`@wordpress/*` updates as `wordpress-packages`; the group comes from the template's
npm additions entry, so earlier vendored templates still render their original
bytes during ownership recovery. Explicit ecosystem lists select
coverage without changing foundation action ownership.
These package manifests and locks are child-owned seeds; sync never overwrites their
project-specific dependency choices. Current starter tooling supports Node.js 22.22.2+, 24.15.0+, or 26+, matching its locked dependency engines.

## Candidate Isolation And Recovery

The scheduled matrix delegates each dependency to `update-external-dependency.yml`.
Each instance has three separate runners:

1. **Prepare** uses a read-only repository token and the reviewed checkout to select
   metadata, download assets, verify available publisher signatures, and stage a
   candidate. It does not execute candidate code. Pin files, platform checksums,
   inventory patterns, and explicit commit paths are prepared together. A failure
   leaves the original files unchanged.
2. **Validate** explicitly selects Node.js 24 and PHP 8.3, then installs and
   exercises the candidate with read-only permissions and no repository secrets. Its filesystem and tool output are never used by the
   publication runner.
3. **Publish** starts from the exact reviewed checkout, downloads the artifact ID
   emitted by preparation, and checks the candidate JSON SHA256 against the trusted
   preparation job output. It also validates the base commit and per-dependency
   path allowlist. Candidate files are treated as data; the publication script and
   all of its dependencies are outside that allowlist. Only the final PR step
   receives the optional publication secret.

A failed dependency instance does not prevent other instances from opening PRs.
Artifact names alone are not an integrity boundary: the artifact ID and candidate
checksum bind publication to preparation even if an unprivileged candidate tries
replacing a same-named artifact. Missing, deleted, corrupt, or mismatched artifacts
fail closed. Rerun the failed dependency job after fixing its failure; do not copy
candidate-generated scripts or outputs into a privileged runner.

Local preparation requires Python 3 in addition to the existing shell tools. Pass
an output path or set `RUNNER_TEMP` to retain the PR body after temporary candidate
cleanup. `scripts/foundation/test_external_dependency_updates.sh` exercises every
handler, inventory consistency, rejected signatures, platform mappings, unsafe
archives, failed downloads, and publication integrity checks without remote writes.

## Publisher Verification And Reviewed Pins

Syft candidates must match its checksum manifest authenticated by the publisher's
`_checksums.txt.sigstore.json` bundle. Detached `.pem`/`.sig` artifacts are no
longer published and are not an unsigned fallback. The verifier requires the
exact `anchore/syft` release workflow identity on `refs/heads/main` and GitHub's OIDC
issuer. Cosign candidates must have valid Sigstore bundles from
`keyless@projectsigstore.iam.gserviceaccount.com` with the Google Accounts issuer.
Both are verified using the previously reviewed Cosign installation, including
certificate and transparency-log verification. Missing or changed publisher
identity requires a reviewed policy change; it never falls back to a fresh hash.

Other external handlers use reviewed metadata and recorded content hashes. These
hashes ensure repeatable bytes after review; they do not independently authenticate
an upstream publisher. Their PR bodies require maintainers to review the upstream
repository, tag, release notes, assets, and source changes before merging. These
candidates execute only in the isolated validation runner. Automatic merging is
not part of this workflow. Major updates remain deliberate compatibility reviews.

See [dependency maintenance](dependency-maintenance.md) for the current security
review, supported update policy, and migration instructions for existing children.

## Private Foundation Source Credentials

GitHub update workflows accept the optional `WP_PLUGIN_BASE_FOUNDATION_TOKEN` secret for read access to a private upstream foundation. Without it, source API and Git requests use `github.token`. On GitLab, provide a protected `GH_TOKEN` for a private GitHub source independently of the destination GitLab credentials. Source fetches use scoped ephemeral Git headers; tokens are not written into remotes or persistent local Git configuration. Redirects carrying API credentials must stay within the configured source origin.

## Change Request Branch Safety

Publication uses the configured provider's scoped, temporary Git authentication
for fetch and push. GitLab project tokens take precedence over the job-token
fallback; credentials are never persisted in remotes or local Git configuration,
and credential-bearing redirects are disabled.

Existing remote branches are updated only by a fast-forward push. If a reviewer
or another process has added commits, a divergent refresh fails and preserves
those commits. Fetch and reconcile the remote branch explicitly, rerun validation,
and retry; automation never force-overwrites reviewer work.
