# PR-Based Changelog Notes

Set `CHANGELOG_SOURCE=change_request_titles` to generate release notes from merged pull request or merge request titles instead of commit subjects.

Legacy alias: `prs_titles` is still accepted and normalized to `change_request_titles` for backward compatibility.

Change-request body section extraction is not implemented in this mode. Changelog entries currently derive from title text plus label/prefix categorization.

Behavior:

- collects merged PRs or MRs whose merge commits are part of the release range
- excludes change requests with labels `dependencies`, `automation`, or `skip-changelog`
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
