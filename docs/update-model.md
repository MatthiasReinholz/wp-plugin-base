# Update Model

Child repos should keep a vendored copy of `wp-plugin-base` in `.wp-plugin-base/`.

The scheduled `update-foundation` workflow:

- reads `FOUNDATION_VERSION`
- checks for a newer compatible foundation tag in the same major series
- pulls the subtree update into `.wp-plugin-base/`
- regenerates managed files from templates
- opens a pull request

Major-version updates are intentionally manual.
