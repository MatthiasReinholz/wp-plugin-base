# PR-Based Changelog Notes

Set `CHANGELOG_SOURCE=change_request_titles` to generate release notes from merged pull request or merge request titles instead of commit subjects.

Legacy alias: `prs_titles` is still accepted and normalized to `change_request_titles` for backward compatibility.

When a change request body contains `## Changelog`, `## Changes`, or `## Release Notes`, the generator uses bullet items from that section first. If no supported section is found, it falls back to the change request title.

Behavior:

- collects merged PRs or MRs whose merge commits are part of the release range
- for body-derived notes:
  - reads only markdown bullets in `## Changelog`, `## Changes`, or `## Release Notes`
  - stops at the next markdown heading
  - supports plain bullets and checked task-list bullets (`- [x] ...`), while ignoring unchecked task-list bullets (`- [ ] ...`)
  - ignores placeholder bullets like `none`, `_none_`, `n/a`
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
