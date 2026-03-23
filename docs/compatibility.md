# Compatibility

The foundation is designed for standard WordPress plugin repos, but it allows a small set of overrides for non-standard layouts.

Supported variation points:

- custom main plugin file name
- optional version constant
- custom readme path
- optional POT file and project name
- custom package include and exclude lists
- custom changelog heading

The foundation does not aim to support arbitrary release conventions. It stays opinionated around semver tags, `main` as the protected release base branch, and WordPress-style changelog sections.
