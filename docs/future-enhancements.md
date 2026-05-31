# Future Enhancements

This page captures possible follow-up work identified during security,
reliability, currency, maintainability, and scalability reviews. These items are
not committed roadmap promises. Each item needs a separate design decision,
implementation plan, and validation scope before it is shipped.

## Review Follow-Ups

- P1: Design a trust-on-first-use or provenance hardening model for external
  release and binary dependency updates before expanding automated updater
  coverage.
- P1: Evaluate WordPress Plugin Check 2.0.0 after the configured stabilization
  window and update the managed tooling pin only after release authenticity and
  compatibility are reviewed.
- P2: Strengthen workflow audit policy so sensitive workflow classification does
  not rely only on workflow file basenames.
- P2: Decide whether the foundation should explicitly enforce expected
  `pull_request_target` workflow presence and scope.
- P2: Evaluate Plugin Update Checker v5.7 and refresh the vendored runtime
  updater pack if the upstream release is authentic and compatible.
- P2: Decide whether the PHP runtime matrix should expand beyond the current
  supported smoke coverage.
- P2: Define a Dependabot policy for optional child/admin UI npm dependency
  templates without creating noisy or misleading downstream update surfaces.
- P3: Add a stale-aware currency report for external pinned tools and release
  security binaries.
- P3: Consider renaming or aliasing the external dependency updater workflow if
  the current `update-plugin-check` filename becomes misleading as more
  dependencies are managed by the same automation.
