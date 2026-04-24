# Runtime In-Dashboard Updater

The runtime updater is an opt-in Layer-2 runtime pack and is disabled by default.

It is distinct from:

- Git-host release publishing
- `wp-core-base` Git-reviewed site update flows

This feature adds classic wp-admin plugin update prompts for plugins distributed through GitHub Releases, GitLab Releases, or a generic JSON metadata endpoint.

It does not replace the authoritative Git host release surface for external automation/downstream consumers. Systems such as `wp-core-base` should continue to consume the selected Git host release, whether or not the plugin ships this optional runtime updater pack.

## Downstream Host Contract

Most projects should use one downstream host profile:

- `AUTOMATION_PROVIDER=github` pairs with `PLUGIN_RUNTIME_UPDATE_PROVIDER=github-release`
- `AUTOMATION_PROVIDER=gitlab` pairs with `PLUGIN_RUNTIME_UPDATE_PROVIDER=gitlab-release`
- `PLUGIN_RUNTIME_UPDATE_PROVIDER=generic-json` is host-agnostic and may be used on either supported host

The foundation release source is a separate upstream concern and may differ from the downstream host.

## Enablement

Set in `.wp-plugin-base.env`:

- `PLUGIN_RUNTIME_UPDATE_PROVIDER=github-release|gitlab-release|generic-json`
- `PLUGIN_RUNTIME_UPDATE_SOURCE_URL=<provider URL>`

Add this line to the plugin main file:

- `require_once __DIR__ . '/lib/wp-plugin-base/wp-plugin-base-runtime-updater.php';`

## Provider Contracts

### `github-release`

- `PLUGIN_RUNTIME_UPDATE_SOURCE_URL` must use `https://github.com/<owner>/<repo>`
- Release publication must attach an installable ZIP asset
- The updater enables release-asset ZIP filtering so SBOM/signature artifacts are ignored
- Do not use this provider unless the downstream repo itself is GitHub-hosted

### `gitlab-release`

- `PLUGIN_RUNTIME_UPDATE_SOURCE_URL` must use the GitLab project web URL, for example `https://gitlab.com/group/project` or `https://<trusted-gitlab-host>/<group>/<project>` for configured self-managed GitLab hosts
- Release publication must attach an installable ZIP asset or release link that resolves to that ZIP
- The updater enables release-asset ZIP filtering so SBOM/signature artifacts are ignored
- Do not use this provider unless the downstream repo itself is GitLab-hosted

### `generic-json`

- `PLUGIN_RUNTIME_UPDATE_SOURCE_URL` must point to an HTTPS JSON metadata document
- The metadata endpoint should expose, at minimum: `version`, `download_url`, `requires`, `tested`, and `requires_php`
- `download_url` must point to the installable ZIP, not to source archives or review artifacts
- Use this provider when the update source is not a supported Git release host or when you need a host-neutral update endpoint
- This provider is a runtime updater transport only; it is not a supported `FOUNDATION_RELEASE_SOURCE_PROVIDER` or native source contract for managed downstream automation consumers such as `wp-core-base`

## Authentication And Secrets

Public repositories are the intended default.

If you enable runtime updates from a private source, do not embed long-lived secrets in `PLUGIN_RUNTIME_UPDATE_SOURCE_URL`. That URL is rendered into the shipped plugin pack, so any token placed there is distributed to end users.

Treat private-repository runtime updates as a constrained-distribution pattern that needs an explicit credential design outside the default foundation contract.

## WordPress.org Collision Risk

Plugins distributed on WordPress.org should usually keep `PLUGIN_RUNTIME_UPDATE_PROVIDER=none`.

If you enable a second update channel for a WordPress.org plugin, you must deliberately handle Plugin Update Checker slug-collision behavior so WordPress.org and the custom updater do not compete for the same install.

## Runtime Pack Content

When enabled, managed sync adds:

- `lib/wp-plugin-base/wp-plugin-base-runtime-updater.php`
- `lib/wp-plugin-base/wp-plugin-base-github-updater.php`
- `lib/wp-plugin-base/plugin-update-checker/*`

The package builder asserts these files are present in `dist` when the feature is enabled.

`GITHUB_RELEASE_UPDATER_ENABLED` and `GITHUB_RELEASE_UPDATER_REPO_URL` remain supported as GitHub-only compatibility aliases and map to the provider-based settings automatically.

## Upstream Version Pin

The runtime pack currently vendors `YahnisElsts/plugin-update-checker` `v5.6`.

Reference source tarball:

- [v5.6 tar.gz](https://github.com/YahnisElsts/plugin-update-checker/archive/refs/tags/v5.6.tar.gz)
- SHA256: `589d2c533464227cd69e8d70515fa2210c59ea8052a08dafd42647285dd5012d`

## Maintainer Checklist

If you change runtime updater behavior in the foundation:

1. update both docs:
   - `docs/distribution-runtime-updater.md`
   - `templates/child/github-release-updater-pack/docs/github-release-updater.md`
   - the `github-release-updater-pack` directory name is intentionally legacy for compatibility; do not rename it as part of a routine docs-only change
2. keep managed pack templates and validation rules consistent:
   - `templates/child/github-release-updater-pack/**`
   - `scripts/ci/validate_project.sh`
   - `scripts/ci/build_zip.sh`
3. run release/update fixture coverage:
   - `bash scripts/foundation/run_release_update_fixture_checks.sh "$PWD"`

## Smoke-Test Recipe

1. Enable updater keys in `.wp-plugin-base.env` and run sync.
2. Add the `require_once` line to the plugin main file.
3. Release `1.0.0`, install that ZIP into a local WordPress site.
4. Release `1.0.1` to the same configured update source.
5. Trigger update checks in wp-admin and verify `1.0.1` appears.
6. Click `Update now` and confirm plugin version updates cleanly.

## References

- [Product layers](layers.md)
- [Security model](security-model.md)
