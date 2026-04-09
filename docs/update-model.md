# Update Model

Your project should keep a vendored copy of `wp-plugin-base` in `.wp-plugin-base/`.

The scheduled `update-foundation` workflow:

- reads `FOUNDATION_VERSION`
- checks for a newer compatible published foundation release in the same major series
- verifies the candidate release provenance by checking the published release metadata asset, its Sigstore bundle, and the tag commit's relationship to `main`
- refreshes the vendored `.wp-plugin-base/` directory from that foundation tag
- regenerates managed files from templates
- opens a pull request

Major-version updates are intentionally manual.
