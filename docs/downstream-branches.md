# Downstream Default Branches

`DEFAULT_BRANCH` defaults to `main`. A plugin may set it to a concrete branch
such as `trunk` or `stable/current`. Configure the same default branch on the
hosting service, protect it, and regenerate managed files before release work.
The setting controls child CI targets, release preparation, merged-release
provenance, update requests, ancestry checks, and GitHub plugin signing identities.
Reusable workflows use the host repository's default branch and reject a
publication config that disagrees with that trusted workflow context.

Names use ASCII letters, digits, dots, underscores, hyphens, and slashes, and must
also pass Git branch validation. Ref namespaces and pull-request pseudo-refs are
rejected. YAML-looking names such as `true` remain literal strings. Certificate
regular expressions escape the complete branch name; no wildcard branch trust is
introduced.

## Changing An Existing Plugin's Branch

1. Preserve the existing release tags and their reviewed configuration unchanged.
2. Protect the replacement branch and set it as the host's default branch.
3. Set `DEFAULT_BRANCH` in the plugin config, run managed sync, and review the
   regenerated workflows and ownership receipt together.
4. Validate the project and merge the migration before preparing a new release.
5. Start subsequent stable release and recovery runs from the configured branch.

An ordinary channel retry verifies the published bytes against the historical
tag's configuration. A tag that predates `DEFAULT_BRANCH` retains the exact
`main` signing identity. Changing today's default branch does not widen that
historical trust. Host-evidence reconstruction requires the original protected
signing branch; it fails when the historical config and executing workflow branch
disagree. Never rewrite old tag configuration or broaden certificate matching to
make recovery pass.

Foundation-source trust is independent: foundation releases continue to require
the foundation's protected `main` release flow. A downstream `trunk` setting does
not change the expected foundation certificate or ancestry. GitLab plugin
signatures remain bound to the exact stable tag rather than a branch identity.

See [release behavior](release-model.md), [local development](local-development.md),
and [package generation and recovery](package-lifecycle.md).
