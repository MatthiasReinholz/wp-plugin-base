# Maintenance Review

Use this page to assess future changes against the foundation's existing contracts.
It is not an unresolved defect list or a commitment to speculative features.

## Implemented Review Outcomes

- External dependency updates separate preparation, candidate execution and
  publication, with artifact identity and digest checks. Publisher verification
  and metadata-only verification are distinguished in the
  [dependency maintenance guide](dependency-maintenance.md).
- Plugin Check and the vendored runtime updater are maintained through reviewed
  pins and the [dependency inventory](dependency-inventory.json).
- Workflow policy inspects privileged behavior and validates the managed action
  catalog. See the [security model](security-model.md).
- Real WordPress runtime coverage and required merge gates are documented in
  [engineering quality](engineering-quality.md).
- Optional child/admin dependency coverage and preserved project ownership are
  documented in the [update model](update-model.md).
- The generic external dependency workflow is the maintained entrypoint; the
  compatibility workflow remains available for existing automation callers.

## Criteria For New Enhancements

Propose a change when a reproducible defect, platform contract change, security
advisory or measured maintenance cost justifies it. Record the affected support
boundary, source-of-truth files, consumer migration and acceptance evidence.
Avoid increasing the managed surface solely to add another configuration option.

Evaluate performance with equivalent checks and repeated measurements. Keep
aggregate runner usage separate from elapsed feedback time. Live host/channel
acceptance is separate from local fixtures; retain the status documented in
[host capabilities](automation-hosts.md).
