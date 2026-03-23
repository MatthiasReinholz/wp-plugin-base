# Update Model

Your project should keep a vendored copy of `wp-plugin-base` in `.wp-plugin-base/`.

The scheduled `update-foundation` workflow:

- reads `FOUNDATION_VERSION`
- checks for a newer compatible published foundation release in the same major series
- refreshes the vendored `.wp-plugin-base/` directory from that foundation tag
- regenerates managed files from templates
- opens a pull request

Major-version updates are intentionally manual.

For that pull request step to work, the repository must enable `Allow GitHub Actions to create and approve pull requests`. If the setting is greyed out, the organization must allow it first. See [Troubleshooting](troubleshooting.md).
