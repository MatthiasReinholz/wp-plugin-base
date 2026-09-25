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

The package build script targets `src/index.js`. That entrypoint is seeded by the shared admin UI seed and imports the selected starter's `src/app.js`, so fresh projects synced through `sync_child_repo.sh` receive both files.

`ADMIN_UI_EXPERIMENTAL_DATAVIEWS=true` remains supported as a backward-compatible alias for `ADMIN_UI_STARTER=dataviews`.

The managed admin page shell emits WordPress' `.wp-header-end` notice marker before the React root so dynamic admin notices are anchored outside the app-rendered header.

The shared API client intentionally separates registry-backed operations from direct REST paths: use `fetchOperation()` for registered operation ids and `fetchPath()` only for explicit raw-path calls.

## DataViews Behavior And Migration

The current experimental starter uses DataViews 19.1 with matching WordPress package versions and requires WordPress 7.1 or later (validated against 7.1.2). Declare `Requires at least: 7.1` or higher in both the plugin header and readme; validation rejects a lower or missing declaration for this starter. The basic starter and REST/Abilities pack retain the WordPress 6.9 boundary test. Treat DataViews package upgrades as explicit compatibility changes: the old 14.3 dependency graph could build successfully while failing at runtime against newer private API packages.

The DataViews stylesheet is imported through `src/dataviews.scss`, so it is bundled as CSS rather than becoming an invalid WordPress script dependency. The managed loader enqueues both `style-index.css` and optional `index.css`, with their generated RTL variants. Keep the generated `index.asset.php` alongside the bundle; it identifies the WordPress-provided scripts required at runtime.

The DataViews starter carries a larger bundle than the basic starter because its public UI components are bundled. Keep `basic` for small settings screens; choose DataViews when its table, filtering, and form behavior justify that payload. Asset budgets remain enforced separately for the selected starter.

The DataViews starter applies `filterSortAndPaginate` to the fetched collection. Search, filters, sorting, and page size reset the view to page 1; pagination totals describe the filtered result. A shrinking collection clamps the current page to the last available page.

Both starters translate status labels in their detail panel. Example operation responses use stable `stable`, `enabled`, and `disabled` status identifiers. Translate their labels in the UI, including the detail panel; do not translate stored values or filter identifiers.

For existing DataViews consumers, these fixes require a reviewed merge into child-owned `.wp-plugin-base-admin-ui/src/app.js`, `src/dataviews.scss`, `package.json`, `package-lock.json`, and `includes/rest-operations/example-items-operations.php`:

1. Reconcile the aligned DataViews 19.1 dependency set with product-specific dependencies and regenerate the lockfile. Include `src/dataviews.scss` and import it from `app.js`; remove the direct JavaScript import of the package CSS.
2. Import `filterSortAndPaginate` from `@wordpress/dataviews`, derive its `data` and `paginationInfo` from the collection, view, and field definitions, and pass both results to `DataViews`.
3. Reset or clamp the page when the query or collection changes.
4. Return stable status identifiers from PHP and translate their display labels in the UI.
5. Preserve product-specific fields, callbacks, and dependencies, rebuild the assets, and test search, filtering, sorting, and page boundaries with more records than one page.

Sync preserves these owned files and will not overwrite local customizations. Compare the corresponding foundation seeds when applying the migration.

## Starter Tooling And Save Behavior

Both starters use `@wordpress/scripts` 36 with explicit React/react-dom 18.3.1
peers for the WordPress runtime. The temporary `typescript-eslint` 8.70.0 override
keeps its package group coherent while the registry's 8.70.1 group is incomplete;
remove it after a complete compatible release passes installation and lint checks.

Existing build, lint and format commands remain supported. Projects using
`test-unit-js` must configure their own Vitest setup or the maintenance Jest
adapter; legacy Puppeteer end-to-end workflows need migration to Playwright.
These starter manifests and sources are child-owned, so apply upgrades explicitly
and preserve project-specific dependencies and tests.

Save controls stay disabled during initial loading and a save, and after an
initial load failure. A synchronous guard also prevents duplicate submissions
before a render updates the controls. Failed saves preserve edits for retry.
Existing children should merge the corresponding handler and control changes
from their matching starter, then test loading failure, rapid submissions, and
save failure/retry behavior in a browser.

## Audit And Update Strategy

When `WORDPRESS_SECURITY_PACK_ENABLED=true`, readiness validation audits `.wp-plugin-base-admin-ui/package-lock.json` with `npm audit --package-lock-only --audit-level=high` by default. Security-sensitive plugins should also set `RELEASE_READINESS_MODE=security-sensitive` so releases fail if the quality pack, security pack, strict Plugin Check, or admin UI audit coverage is weakened.

Readiness validation also reports and enforces raw and gzip admin UI asset budgets for the built `assets/admin-ui/` tree. Override `WP_PLUGIN_BASE_ADMIN_UI_MAX_SCRIPT_BYTES`, `WP_PLUGIN_BASE_ADMIN_UI_MAX_SCRIPT_GZIP_BYTES`, `WP_PLUGIN_BASE_ADMIN_UI_MAX_STYLE_BYTES`, `WP_PLUGIN_BASE_ADMIN_UI_MAX_STYLE_GZIP_BYTES`, `WP_PLUGIN_BASE_ADMIN_UI_MAX_TOTAL_BYTES`, or `WP_PLUGIN_BASE_ADMIN_UI_MAX_TOTAL_GZIP_BYTES` only when the larger runtime payload is intentional and reviewed.

Resolve admin UI audit findings by updating the pinned `@wordpress/*` packages through the generated Dependabot path or by adding the narrowest possible npm `overrides` entry in the child-owned `.wp-plugin-base-admin-ui/package.json`. If a finding is limited to the build-only WordPress toolchain and no patched upstream version exists yet, `ADMIN_UI_NPM_AUDIT_LEVEL=critical` is a temporary compatibility override only outside `RELEASE_READINESS_MODE=security-sensitive`; document why it is safe and remove it after the upstream package is updated.

Admin starter files are child-owned and seeded once. Changing `ADMIN_UI_STARTER` after the first sync does not rewrite those files; project validation will fail until the starter files are reconciled manually or re-seeded intentionally.

Disabling `ADMIN_UI_PACK_ENABLED` is also a manual reconciliation step. Sync removes the managed bootstrap, but it does not rewrite child-owned plugin entrypoints or seeded sources. Remove the `require_once __DIR__ . '/lib/wp-plugin-base/admin-ui/bootstrap.php';` line from the main plugin file, clear `BUILD_SCRIPT=.wp-plugin-base-admin-ui/build.sh`, and delete stale `assets/admin-ui/` build outputs before packaging. Deleting the seeded `.wp-plugin-base-admin-ui/` sources is optional but recommended once the pack is intentionally removed.

The app seeds keep the WordPress ESLint correctness rules enabled. Their file-level formatting rule is disabled because generated plugin names and text domains change Prettier line wrapping. Format your child-owned app with `npm run format` from `.wp-plugin-base-admin-ui/` and remove that formatting suppression when adopting your own formatting policy.
