# Runtime Updater

This file is managed by `wp-plugin-base` when `PLUGIN_RUNTIME_UPDATE_PROVIDER!=none`.

## Required project config

Add to `.wp-plugin-base.env`:

- `PLUGIN_RUNTIME_UPDATE_PROVIDER=github-release|gitlab-release|generic-json`
- `PLUGIN_RUNTIME_UPDATE_SOURCE_URL=<provider URL>`

Host-backed providers must match the selected downstream host:

- `github-release` requires `AUTOMATION_PROVIDER=github`
- `gitlab-release` requires `AUTOMATION_PROVIDER=gitlab`
- `generic-json` is host-agnostic

This runtime updater does not replace the authoritative Git host release surface for external automation/downstream consumers. Systems such as `wp-core-base` should continue to consume the selected Git host release.

## Required plugin bootstrap include

Add to your main plugin file exactly once:

```php
require_once __DIR__ . '/lib/wp-plugin-base/wp-plugin-base-runtime-updater.php';
```

## What this provides

- WordPress in-dashboard update checks for the configured runtime update provider.
- Release asset ZIP filtering to avoid SBOM/signature artifacts.
- No behavior change unless explicitly enabled.
- Do not embed long-lived secrets in `PLUGIN_RUNTIME_UPDATE_SOURCE_URL`.
- `generic-json` is a runtime updater transport only, not a supported `FOUNDATION_RELEASE_SOURCE_PROVIDER` or native source contract for managed downstream automation.

## Local smoke test

1. Release `1.0.0` and install that ZIP into a local WordPress site.
2. Publish `1.0.1` through the same configured update source.
3. Trigger plugin update checks in wp-admin.
4. Confirm the `1.0.1` update appears and installs cleanly.
