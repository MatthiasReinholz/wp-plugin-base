# GitHub Release Updater

This file is managed by `wp-plugin-base` when `GITHUB_RELEASE_UPDATER_ENABLED=true`.

## Required project config

Add to `.wp-plugin-base.env`:

- `GITHUB_RELEASE_UPDATER_ENABLED=true`
- `GITHUB_RELEASE_UPDATER_REPO_URL=https://github.com/<owner>/<repo>`

## Required plugin bootstrap include

Add to your main plugin file exactly once:

```php
require_once __DIR__ . '/lib/wp-plugin-base/wp-plugin-base-github-updater.php';
```

## What this provides

- WordPress in-dashboard update checks for GitHub Releases.
- Release asset ZIP filtering to avoid SBOM/signature artifacts.
- No behavior change unless explicitly enabled.
