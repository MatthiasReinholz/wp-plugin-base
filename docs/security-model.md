# Security Model

`wp-plugin-base` treats workflow code, release scripts, and foundation updates as privileged infrastructure.

## Default Policy

The intended default for the foundation repository and every project that consumes it is:

- GitHub-hosted runners
- local workflow files committed in the project repository
- vendored foundation source committed under `.wp-plugin-base/`
- external actions pinned to full commit SHAs
- a short allowlist of approved actions
- read-only workflow permissions by default, with narrowly scoped write permissions only where required

## Approved Actions

The current hardened baseline allows only these external actions:

- `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd`
- `actions/setup-node@53b83947a5a98c8d113130e565377fae1a50d02f`
- `actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a`
- `actions/attest-build-provenance@a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32`
- `github/codeql-action/upload-sarif@c10b8064de6f491fea524254123dbe5e09572f13`
- `ossf/scorecard-action@4eaacf0543bb3f2c246792bd56e8cdeffafb205a`
- `shivammathur/setup-php@accd6127cb78bee3e8082180cb391013d204ef9f`

The foundation intentionally does not depend on `peter-evans/create-pull-request`, `softprops/action-gh-release`, or `10up/action-wordpress-plugin-deploy`. Those duties are handled by repo-local scripts using `gh` or `svn`.

## GitHub Actions Settings

Prefer configuring this at the organization level. If that is not possible, configure it per repository under `Settings` -> `Actions` -> `General`.

Recommended settings:

1. `Actions permissions`: `Allow OWNER, and select non-OWNER, actions and reusable workflows`
2. Allow GitHub-authored actions
3. Allow only the specific non-GitHub actions required by the current foundation version
4. Enable `Require actions to be pinned to a full-length commit SHA`
5. Under `Workflow permissions`, use `Read and write permissions` only because release and update workflows need repository writes
6. Enable `Allow GitHub Actions to create and approve pull requests` if you want `prepare-release` or `update-foundation` to open PRs

## Workflow Audit Gate

Foundation CI and generated project CI run `scripts/ci/audit_workflows.sh`.

That audit fails if it finds:

- an external action not pinned to a 40-character commit SHA
- an external action outside the approved allowlist
- a local action whose `runs.using` is not `composite`
- a composite local action that dispatches to a repo-local helper script through `node`, `python`, `bash`, or another interpreter instead of inlining the audited commands
- a workflow without explicit top-level `permissions`
- a workflow with broader permissions than its policy allows
- a custom workflow with privileged scopes outside the read-only policy, including `contents: write`, `pull-requests: write`, `id-token: write`, or `attestations: write`
- `curl | bash`, `curl | python`, `wget | sh`, multiline download-then-exec payloads, or any equivalent remote-script execution
- a workflow or local action run body that builds a download URL dynamically instead of using a literal auditable host
- outbound URLs to hosts outside the documented allowlist
- any `pull_request_target` workflow outside the audited managed finalize workflows
- an audited `pull_request_target` workflow whose job condition differs from the exact reviewed merge-gating expression

## Allowed Network Destinations

The hardened baseline audits literal workflow and repo-local-script references to these hosts:

- `api.github.com`
- `github.com`
- `uploads.github.com`
- `downloads.wordpress.org`
- `plugins.svn.wordpress.org`
- `woocommerce.com`
- `auth.docker.io`
- `registry-1.docker.io`
- `token.actions.githubusercontent.com`

Projects can extend this allowlist with `EXTRA_ALLOWED_HOSTS` in `.wp-plugin-base.env` when additional trusted hosts are required. Use hostnames only and keep this list minimal.

Dynamic URL construction inside workflow or local-action `run:` bodies is intentionally out of contract. Those contexts must use literal auditable hosts or delegate the network call to a reviewed repo-local script.

This allowlist is not a full runner egress firewall. Package-manager traffic and other tool-internal network access are controlled separately by the reviewed bootstrap scripts. Foundation CI installs the Python lint toolchain from hash-pinned requirements files and the Node lint toolchain from a committed `package-lock.json`.

Ubuntu package mirrors are only expected indirectly when the workflow installs Subversion with `apt-get`.

### WooCommerce.com Marketplace Deploy

When `WOOCOMMERCE_COM_DEPLOY_ENABLED=true`, release workflows call:

- `https://woocommerce.com/wp-json/wc/submission/runner/v1/product/deploy/status`
- `https://woocommerce.com/wp-json/wc/submission/runner/v1/product/deploy`

Authentication uses Woo username and WordPress application password as multipart form fields (`WOO_COM_USERNAME`, `WOO_COM_APP_PASSWORD`), not HTTP basic auth headers.

See [WooCommerce.com distribution](distribution-woocommerce-com.md) for operator setup and repair workflow details.

### GitHub Release Updater Runtime

When `GITHUB_RELEASE_UPDATER_ENABLED=true`, managed files include a vendored copy of Plugin Update Checker in `lib/wp-plugin-base/plugin-update-checker/`.

Runtime update checks then occur from customer WordPress sites to GitHub API endpoints under `api.github.com`. These runtime calls are outside CI host auditing scope.

See [GitHub Release updater distribution](distribution-github-release-updater.md) for runtime behavior and testing guidance.

## Release And Update Provenance

Foundation updates are not allowed to trust arbitrary tags.

Before `update-foundation` opens a PR, it verifies:

- the target foundation release is published
- the release is not a draft or prerelease
- the tag matches the `vX.Y.Z` contract
- the tagged commit is reachable from the foundation repository's `main`
- the tagged commit was produced by a merged `release/vX.Y.Z` or `hotfix/vX.Y.Z` pull request into `main`
- the release author is on the allowed author list
- the vendored refresh is performed from the verified commit SHA, not by re-resolving the tag later

Consumers can also verify a released plugin ZIP independently after downloading it from GitHub Releases:

```bash
gh attestation verify --owner <github-owner> path/to/plugin.zip
```

That verifies the GitHub build attestation attached to the published release artifact without relying on local trust in the release notes alone.

Release workflows now also attach a CycloneDX SBOM for the packaged artifact contents and a Sigstore keyless bundle for the released blob. Those cover different trust questions:

- attestation answers "was this built by the expected GitHub workflow?"
- SBOM answers "what dependencies and packages were present in the released contents?"
- cosign bundle answers "can I verify this exact release blob independently with Sigstore tooling?"

Strict verification flow for a released plugin ZIP:

```bash
gh release download <tag> --pattern '<plugin-zip>' --pattern '<plugin-zip>.sigstore.json'
bash .wp-plugin-base/scripts/release/verify_sigstore_bundle.sh \
  <owner>/<repo> \
  <plugin-zip> \
  <plugin-zip>.sigstore.json \
  plugin
```

The strict verifier only trusts signatures produced by the expected release workflows on `refs/heads/main`. Foundation update verification also downloads the signed `dist-foundation-release.json` metadata asset and its Sigstore bundle, verifies the bundle, and compares the repository, version, and commit fields against the selected release before any vendored code is refreshed. If the newest compatible release fails those checks, the updater falls back to the next older compatible published release instead of trusting the broken candidate.

If you intentionally need a different branch policy, treat it as an explicit policy change and document it in the repository that consumes the verifier.

The foundation repository's `scorecard` workflow publishes Scorecard SARIF results to the GitHub Security tab on the default branch. That provides an external, machine-generated view of branch protection, token permissions, dependency update posture, and related repository hygiene.

## Public Endpoint Suppressions

`scripts/ci/scan_wordpress_authorization_patterns.sh` blocks risky public endpoint patterns by default:

- `wp_ajax_nopriv_*`
- `admin_post_nopriv_*`
- REST routes with `permission_callback => __return_true`

Intentional exceptions must be declared in `.wp-plugin-base-security-suppressions.json` (or a custom path via `WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE`) using this structure:

```json
{
  "suppressions": [
    {
      "kind": "wp_ajax_nopriv",
      "identifier": "my_public_action",
      "path": "includes/class-public-endpoints.php",
      "justification": "Explain why public access is required and what guards make it safe."
    }
  ]
}
```

Suppressions without non-empty justifications are rejected. Supported `kind` values are `wp_ajax_nopriv`, `admin_post_nopriv`, `rest_permission_callback_true`, `rest_public_operation`, and `rest_route_bypass`.

When `REST_OPERATIONS_PACK_ENABLED=true`, intentionally public operations declared through the managed operation registry must also carry a `rest_public_operation` suppression keyed by the operation id and the leaf declaration file such as `includes/rest-operations/settings-operations.php`.
If a project deliberately keeps a legacy `register_rest_route()` call outside the managed operation registry during a migration, that file must carry a `rest_route_bypass` suppression with `identifier: "register_rest_route"` and a written justification.

For agent-oriented implementation guidance, see [Secure plugin coding contract](secure-plugin-coding-contract.md).

## Secrets And Environments

- Prefer `GITHUB_TOKEN` over personal access tokens
- Do not add PAT-based automation to projects using this foundation unless there is no GitHub-native alternative
- The explicit exception is workflow-changing update automation: if `update-foundation` or `update-external-dependencies` must push `.github/workflows/*`, configure `WP_PLUGIN_BASE_PR_TOKEN` with the minimum repository permissions required to write contents, pull requests, and workflows
- Keep WordPress.org credentials in GitHub Actions deployment-environment secrets, not in `.wp-plugin-base.env` or repository-wide secrets
- Protect the production deployment environment and require at least one reviewer before deploy jobs can access those credentials

## Governance

Changes to these paths should require maintainer review:

- `.github/workflows/**`
- `templates/child/.github/workflows/**`
- `scripts/**`
- `.github/dependabot.yml`

The foundation repository includes CODEOWNERS rules for that scope. Projects can opt into generated CODEOWNERS rules by setting `CODEOWNERS_REVIEWERS` in `.wp-plugin-base.env`.

## Emergency Response

If a GitHub Action or automation dependency is reported compromised:

1. disable the affected workflow or job
2. remove the affected action from the allowlist
3. rotate any credentials that may have been exposed
4. cut a new foundation release with the replacement or removal
5. use `update-foundation` or a manual sync PR to roll the fix into project repositories
The scheduled external dependency updater workflow (`.github/workflows/update-plugin-check.yml`, displayed in Actions UI as `update-external-dependencies`) uses a narrower trust model for third-party dependencies than for first-party foundation updates. It opens reviewable PRs for pinned external dependencies by reading release metadata, refreshing pinned versions and hashes, and committing only the managed files declared by each dependency handler.

For `WordPress/plugin-check`, the updater only proposes automated pin bumps when:

- the release is published, non-draft, and non-prerelease
- the tag stays within the current major version series
- the release author is on the allowed author list
- the release has aged past the configured stabilization window before automation proposes it

External GitHub dependency update workflows should use the shared PR-body helper and declare their trust mode explicitly. When first-party provenance cannot be verified automatically, the framework still allows automation but adds a standardized reviewer warning to the PR telling reviewers to verify the upstream repository, tag, release notes, and release assets before merge.

That keeps external dependency updaters automated without treating raw release metadata as equivalent to first-party provenance.

See also:

- [Update model](update-model.md)
- [Release model](release-model.md)
