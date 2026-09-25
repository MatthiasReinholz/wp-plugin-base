# Real Runtime Contracts

Run the generated plugin against an explicit WordPress/PHP pair:

```bash
WP_PLUGIN_BASE_TEST_WP_CORE=WordPress/WordPress#7.1.2 \
WP_PLUGIN_BASE_TEST_PHP_VERSION=8.3 \
bash scripts/foundation/test_runtime_packs_wordpress.sh
```

The default runs both admin starters. `WP_PLUGIN_BASE_TEST_ADMIN_VARIANT=basic` or `dataviews` selects one. The WordPress 6.9 Abilities boundary is tested with the basic starter; the current DataViews dependency set is tested on WordPress 7.1.2. Docker, Node/npm, PHP and the ordinary foundation tooling must be available.

The runner builds and lints the generated sources, starts an isolated WordPress installation, exercises real REST and Abilities contracts, and checks that every generated script dependency resolves in WordPress. The DataViews lane also installs the pinned Playwright Chromium browser and runs two browser tests:

- `dataviews-browser.cjs` bundles the actual starter and installed WordPress packages with a controlled 25-record API fixture. It verifies search, sorting, filtering, translated status labels, query page resets, filtered totals, and last-page boundaries.
- `wordpress-admin-browser.cjs` loads the production bundle inside WordPress, signs in to the disposable wp-env site, queries the real seeded REST operations, and saves/reloads settings. It detects errors hidden by build-only tests and queued-script checks.

The API fixture is used only in the standalone browser test. The WordPress browser test uses real REST requests. `WP_PLUGIN_BASE_TEST_BROWSER_CHANNEL` can select an installed Playwright browser channel; omit it to use the downloaded Chromium.

A single installed DataViews package can be checked without starting WordPress:

```bash
node tests/runtime/dataviews-browser.cjs /absolute/path/to/.wp-plugin-base-admin-ui
```

Use fixtures and local wp-env credentials only. These scripts are foundation tests and are not included in a plugin release package.
