# Managed Files

These files are intended to be generated from foundation templates in your project:

- `.github/dependabot.yml`
- `.github/workflows/ci.yml`
- `.github/workflows/prepare-release.yml`
- `.github/workflows/finalize-release.yml`
- `.github/workflows/release.yml`
- `.github/workflows/update-foundation.yml`
- `.distignore`
- `CONTRIBUTING.md`

Do not hand-edit those files in your project unless you are intentionally diverging from the foundation. If you need a permanent change, make it in `wp-plugin-base` and resync.

`finalize-release.yml` is the standard automated publish path. `release.yml` is the manual recovery workflow for an already existing tag. `.github/dependabot.yml` keeps GitHub Actions pins moving through reviewable PRs.
