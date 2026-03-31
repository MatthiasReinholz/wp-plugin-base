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
- `actions/upload-artifact@bbbca2ddaa5d8feaa63e36b76fdaad77386f024f`
- `actions/attest-build-provenance@a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32`
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
- a workflow without explicit top-level `permissions`
- a workflow with broader permissions than its policy allows
- `curl | bash`, `wget | sh`, or equivalent remote-script execution
- outbound URLs to hosts outside the documented allowlist
- `pull_request_target` workflows that are not limited to merged internal release or hotfix branches

## Allowed Network Destinations

The hardened baseline only allows workflow/script references to:

- `api.github.com`
- `github.com`
- `uploads.github.com`
- `plugins.svn.wordpress.org`

Ubuntu package mirrors are only expected indirectly when the workflow installs Subversion with `apt-get`.

## Release And Update Provenance

Foundation updates are not allowed to trust arbitrary tags.

Before `update-foundation` opens a PR, it verifies:

- the target foundation release is published
- the release is not a draft or prerelease
- the tag matches the `vX.Y.Z` contract
- the tagged commit is reachable from the foundation repository's `main`
- the tagged commit was produced by a merged `release/vX.Y.Z` or `hotfix/vX.Y.Z` pull request into `main`
- the release author is on the allowed author list

## Secrets And Environments

- Prefer `GITHUB_TOKEN` over personal access tokens
- Do not add PAT-based automation to projects using this foundation unless there is no GitHub-native alternative
- Keep WordPress.org credentials in GitHub Actions environment secrets when possible, not repository-wide secrets
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
