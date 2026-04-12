# GitHub Release In-Dashboard Updater

The GitHub Release updater is an opt-in Layer-2 runtime pack and is disabled by default.

It is distinct from:

- GitHub release publishing (already part of release workflows)
- `wp-core-base` Git-managed site update flow

This feature adds classic wp-admin plugin update prompts for plugins that are distributed through GitHub Releases.

## Enablement

Set in `.wp-plugin-base.env`:

- `GITHUB_RELEASE_UPDATER_ENABLED=true`
- `GITHUB_RELEASE_UPDATER_REPO_URL=https://github.com/<owner>/<repo>`

Add this line to the plugin main file:

- `require_once __DIR__ . '/lib/wp-plugin-base/wp-plugin-base-github-updater.php';`

## Runtime Pack Content

When enabled, managed sync adds:

- `lib/wp-plugin-base/wp-plugin-base-github-updater.php`
- `lib/wp-plugin-base/plugin-update-checker/*`

The package builder asserts these files are present in `dist` when the feature is enabled.

## PUC Asset Selection

The updater bootstrap enables GitHub release asset support and filters release assets to ZIP names only. This prevents accidental selection of non-install assets such as SBOM or signature files.

## Upstream Version Pin

The runtime pack currently vendors `YahnisElsts/plugin-update-checker` `v5.6`.

Reference source tarball:

- [v5.6 tar.gz](https://github.com/YahnisElsts/plugin-update-checker/archive/refs/tags/v5.6.tar.gz)
- SHA256: `589d2c533464227cd69e8d70515fa2210c59ea8052a08dafd42647285dd5012d`

## Private Repositories

PUC can authenticate to private repositories, but embedding long-lived tokens in customer-installed plugins is high risk. Treat private-repo updater deployments as constrained-distribution scenarios with explicit credential governance.

## Relationship to `wp-core-base`

- This updater is plugin-level pull behavior from customer WordPress sites into wp-admin update UI.
- `wp-core-base` is site-level Git governance that opens PRs in the downstream site repository and typically suppresses wp-admin update prompts for managed plugins.
- Both can coexist: in Git-governed sites, policy can ignore/suppress in-dashboard offers; in unmanaged sites, this updater provides standard WordPress update UX.

## Validation Contract

When enabled, project validation enforces:

- updater include line exists in the main plugin file
- updater repo URL uses `https://github.com/<owner>/<repo>` format

## Maintainer / Agent Checklist

If you change updater behavior in the foundation:

1. update both docs:
   - `docs/distribution-github-release-updater.md`
   - `templates/child/github-release-updater-pack/docs/github-release-updater.md`
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
4. Release `1.0.1` to the same GitHub repository.
5. Trigger update checks in wp-admin and verify `1.0.1` appears.
6. Click `Update now` and confirm plugin version updates cleanly.

## References

- [Product layers](layers.md)
- [Security model](security-model.md)
