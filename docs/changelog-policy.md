# Changelog Policy

Use `CHANGELOG.md` for user-visible release notes.

Guidelines:

- keep one `## vX.Y.Z` section per foundation release
- do not keep a persistent `## Unreleased` section in the foundation changelog; use release PR bodies for draft notes, then publish notes under the concrete release version
- prefer concise bullet points that describe behavior or contract changes
- use `* Add -`, `* Fix -`, `* Tweak -`, `* Update -`, or `* Dev -` prefixes in release branch readme changelog sections
- avoid commit-subject dumps when a short summary is clearer
- update generated notes before merging a release PR if the automatic output is too thin
