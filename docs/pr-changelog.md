# PR-Based Changelog Notes

Set `CHANGELOG_SOURCE=prs_titles` to generate release notes from merged pull request titles instead of commit subjects.

PR-body section extraction is not implemented in this mode. Changelog entries currently derive from PR titles plus label/prefix categorization.

Behavior:

- collects merged PRs whose merge commits are part of the release range
- excludes PRs with labels `dependencies`, `automation`, or `skip-changelog`
- applies category prefixes in this order:
  - explicit title prefixes (`Add`, `Fix`, `Tweak`, `Update`, `Dev`)
  - label mapping (`bug` -> `Fix`, `enhancement` -> `Add`, `performance` -> `Tweak`, `documentation` -> `Dev`)
  - fallback `Update`

The generator emits WordPress readme bullet format:

- `* Add - ...`
- `* Fix - ...`
- `* Tweak - ...`
- `* Update - ...`
- `* Dev - ...`
