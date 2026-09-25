# Automation Host Capabilities

GitHub is the primary continuously tested automation host. GitLab provides a separate host profile with local contract tests; a configured GitLab runner must complete the acceptance checklist below before production use. Local mocks do not establish parity with a live hosted service.

| Capability | GitHub | GitLab |
| --- | --- | --- |
| Project validation | Managed workflow | Managed pipeline, including merge requests |
| WordPress readiness | Managed job | Managed job; Docker-capable runtime required |
| PHP runtime matrix | Configured setup-php matrix | Generated child pipeline; reviewed image mapping required |
| Release preparation | Pull request | Merge request |
| Release trigger | Verified release PR merge; controlled manual repair | Annotated tag from main with verified release MR |
| Release provenance | GitHub OIDC, exact workflow identity | Sigstore audience ID token, exact project/tag identity |
| Channel retry | Verified published artifacts | Verified published artifacts |
| Manual QIT workflow pack | Managed optional workflow | Project-owned automation; GitHub pack toggle rejected |
| Woo status diagnostics | Separate optional workflow | Inspect vendor status through channel tooling |
| Dependency updates | Managed Dependabot for selected manifests | Configure a project-owned dependency update service |
| Foundation updates | Verified GitHub/GitLab foundation source | Same source verification; source credentials separate from destination credentials |

## GitLab Runtime Contract

The fallback image is digest-pinned Ubuntu. Its distribution packages do not necessarily match the PHP and Node versions in the project config. Every job verifies actual versions before running project code. A mismatch is an error; the pipeline never silently substitutes Ubuntu's versions.

For a production runner, set `WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGE` to a reviewed image ending in `@sha256:<64 lowercase hex characters>` and `WP_PLUGIN_BASE_GITLAB_BOOTSTRAP_APT=false`. Provision `git`, PHP, Node/npm, Ruby, Perl, Python 3, jq, rsync, curl, zip/unzip, CA certificates, and Subversion when deploying to WordPress.org. PHP and Node must match `PHP_VERSION` and `NODE_VERSION`. Use a Docker-capable runner and client for WordPress readiness and strict runtime checks. Maintain the image and its tool dependencies as an upstream platform asset.

For `PHP_RUNTIME_MATRIX`, set `WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGES` to a JSON object mapping each configured PHP version to its own provisioned digest-pinned image. Each image must use the same configured Node version. Matrix jobs verify the selected PHP version inside the container before running the smoke/strict checks. Missing mappings fail pipeline generation. No matrix is silently skipped when configured.

Tag jobs require complete Git history (`GIT_DEPTH=0`). Protect stable tags and the production environment. Configure the release identity token with audience `sigstore`; do not substitute a personal access token for the OIDC token. A GitHub-hosted private foundation source also requires its own `GH_TOKEN`, even when the destination project uses GitLab credentials. GitHub children can supply the optional `WP_PLUGIN_BASE_FOUNDATION_TOKEN` secret with read access to a private foundation repository; otherwise the source fetch uses `github.token`. Keep this credential separate from the token used to create the destination update PR.

## Host Acceptance Checklist

Use a disposable project and non-production channel destinations:

1. Run merge-request validation, readiness and every configured runtime matrix job; deliberately mismatch a runtime to prove rejection.
2. Prepare and merge a release MR; create the annotated stable tag from that commit.
3. Verify the signed host assets with the expected tag identity, then inspect downstream channel ordering.
4. Fail a channel after host publication and retry; confirm the exact published ZIP is reused.
5. Retry an older version; confirm latest and WordPress.org trunk do not move backward.
6. Run a scheduled foundation update from the selected source host and inspect its MR.

Record project, runner image digest, commit, job URLs and artifact checksums. Do not claim live host acceptance from fixture results alone.

Historical pipeline definitions are not retroactively upgraded. See [historical workflow recovery](troubleshooting.md#historical-workflow-runs) before retrying releases created with older automation.

Private GitLab release upload recovery uses the authenticated upload-by-secret API, available in GitLab 17.4 or newer. Older self-managed instances need an upgrade before using that recovery path.
