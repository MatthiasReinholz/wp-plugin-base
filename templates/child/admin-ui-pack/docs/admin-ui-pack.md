# Admin UI Pack

Enable `ADMIN_UI_PACK_ENABLED=true` to sync the managed admin UI bootstrap into your project.

This pack uses a hybrid ownership model:

- managed under `lib/wp-plugin-base/admin-ui/` and `.wp-plugin-base-admin-ui/shared/`
- child-owned under `includes/admin-ui/` and `.wp-plugin-base-admin-ui/src/`

## Required Main Plugin Include

Add this line to your plugin main file:

```php
require_once __DIR__ . '/lib/wp-plugin-base/admin-ui/bootstrap.php';
```

## Build Convention

Set:

```bash
BUILD_SCRIPT=.wp-plugin-base-admin-ui/build.sh
```

The managed wrapper runs `npm ci` and `npm run build` inside `.wp-plugin-base-admin-ui/` and emits built assets into `assets/admin-ui/`.

## Default Stack

The initial pack targets WordPress-native admin apps:

- `@wordpress/components`
- `@wordpress/api-fetch`
- `@wordpress/data`
- `@wordpress/dataviews` for the optional experimental variant
- `@wordpress/i18n`
- `@wordpress/element`
- `@wordpress/scripts`

`ADMIN_UI_STARTER=basic|dataviews` selects which child-owned admin starter is seeded when the pack is enabled. `basic` is the normalized default lighter component-only starter when the key is omitted. `dataviews` seeds the DataForm/DataViews starter.

`ADMIN_UI_EXPERIMENTAL_DATAVIEWS=true` remains supported as a backward-compatible alias for `ADMIN_UI_STARTER=dataviews`.

The shared API client intentionally separates registry-backed operations from direct REST paths: use `fetchOperation()` for registered operation ids and `fetchPath()` only for explicit raw-path calls.

## Audit And Update Strategy

When `WORDPRESS_SECURITY_PACK_ENABLED=true`, readiness validation audits `.wp-plugin-base-admin-ui/package-lock.json` with `npm audit --package-lock-only --audit-level=high` by default. Security-sensitive plugins should also set `RELEASE_READINESS_MODE=security-sensitive` so releases fail if the quality pack, security pack, strict Plugin Check, or admin UI audit coverage is weakened.

Readiness validation also reports and enforces raw and gzip admin UI asset budgets for the built `assets/admin-ui/` tree. Override `WP_PLUGIN_BASE_ADMIN_UI_MAX_SCRIPT_BYTES`, `WP_PLUGIN_BASE_ADMIN_UI_MAX_SCRIPT_GZIP_BYTES`, `WP_PLUGIN_BASE_ADMIN_UI_MAX_STYLE_BYTES`, `WP_PLUGIN_BASE_ADMIN_UI_MAX_STYLE_GZIP_BYTES`, `WP_PLUGIN_BASE_ADMIN_UI_MAX_TOTAL_BYTES`, or `WP_PLUGIN_BASE_ADMIN_UI_MAX_TOTAL_GZIP_BYTES` only when the larger runtime payload is intentional and reviewed.

Resolve admin UI audit findings by updating the pinned `@wordpress/*` packages through the generated Dependabot path or by adding the narrowest possible npm `overrides` entry in the child-owned `.wp-plugin-base-admin-ui/package.json`. If a finding is limited to the build-only WordPress toolchain and no patched upstream version exists yet, `ADMIN_UI_NPM_AUDIT_LEVEL=critical` is a temporary compatibility override only outside `RELEASE_READINESS_MODE=security-sensitive`; document why it is safe and remove it after the upstream package is updated.

Admin starter files are child-owned and seeded once. Changing `ADMIN_UI_STARTER` after the first sync does not rewrite those files; project validation will fail until the starter files are reconciled manually or re-seeded intentionally.

Disabling `ADMIN_UI_PACK_ENABLED` is also a manual reconciliation step. Sync removes the managed bootstrap, but it does not rewrite child-owned plugin entrypoints or seeded sources. Remove the `require_once __DIR__ . '/lib/wp-plugin-base/admin-ui/bootstrap.php';` line from the main plugin file, clear `BUILD_SCRIPT=.wp-plugin-base-admin-ui/build.sh`, and delete stale `assets/admin-ui/` build outputs before packaging. Deleting the seeded `.wp-plugin-base-admin-ui/` sources is optional but recommended once the pack is intentionally removed.
