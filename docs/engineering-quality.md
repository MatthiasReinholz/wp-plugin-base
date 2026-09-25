# Engineering Quality And Evaluation

The foundation's purpose is repeatable governance across a portfolio of WordPress plugins: maintained child automation, verified foundation upgrades, package policy, release evidence, and optional runtime packs. A single plugin that only needs a release wizard may be better served by a smaller release tool.

## Merge And Validation Policy

Main requires these GitHub Actions checks with an up-to-date base:

- `Validate foundation (PHP 8.2)`
- `Validate full foundation suite (PHP 8.2)`
- `Validate strict-local bootstrap`
- `Release security smoke`

Clean strict bootstrap runs independently alongside ordinary validation, the full suite and the real WordPress runtime matrix. The stable required strict bootstrap check aggregates these four prerequisites with `always()` and explicitly fails unless every named prerequisite succeeds; this avoids GitHub treating a skipped required job as a passing gate. Preserve these check names or migrate the repository rules in the same maintenance window. The rule is repository state; changing a workflow file alone does not enforce it.

New commits to the same pull request cancel obsolete foundation CI runs; unrelated pull requests and branches retain separate concurrency groups. Version-independent policy and full packaging fixtures run once. Separate real WordPress jobs select the container's PHP version explicitly for PHP 8.2–8.5, plus the WordPress 6.9 Abilities boundary. Current WordPress coverage is pinned to 7.1.2. Update that pin when reviewing WordPress releases; do not confuse the runner's PHP version with the WordPress container's version. PHP 8.1 is no longer part of the supported foundation CI matrix.

The primary validation and clean-bootstrap jobs install and verify Subversion so native local-repository deployment tests run instead of being skipped. These qualify package publication mechanics without accessing a live WordPress.org account.

## Repeatable Engineering Evaluation

Evaluate proposed changes against the previous stable foundation using equivalent disposable plugin fixtures, fixed tool versions and the same runner size. Preserve logs and artifact digests. Use at least five successful repetitions for elapsed-time comparisons, report median and range, and report cold and warm caches separately.

| Scenario | Required observations |
| --- | --- |
| First adoption | Hands-on setup time, changed files, required credentials and successful first package |
| Ordinary release | Total elapsed time, runner minutes, manual steps and artifact contents |
| Failed channel and retry | Recovery time, operator decisions, duplicate publication and artifact identity |
| Older release replay | Whether latest/channel state can regress |
| Dependency/security update | Detection-to-PR latency, review burden and failed-update recovery |
| Fleet update | Per-plugin intervention, preserved customizations and rollout failures |

Use `scripts/foundation/report_ci_cost.sh <repository> <run-id>` to capture GitHub job durations without changing the repository or run. Keep equivalent runtime/security coverage in the benchmark report. Job duration totals are an approximation of runner usage, not billing data. GitLab acceptance and live channel benchmarks remain separate evidence from local fixtures.

## Maintenance Boundaries

Keep security-sensitive state transitions in small release helpers. Add a focused negative test when a new trust boundary or external contract is introduced. The large legacy release fixture suite remains a regression backstop; new independently runnable contract suites should own new scenarios rather than expanding that file indefinitely.

Before changing a generated surface, consult [the maintainer map](maintainer-agent-map.md), [file ownership](managed-files.md), and [host capabilities](automation-hosts.md). Compare tool versions and advisory results as separate dimensions: a newer major version can introduce compatibility risk even when the current compatible dependency tree has no known advisory.

## Optional UI Cost

The public DataViews 19 starter bundles approximately 851 KB of JavaScript (196 KB gzip) plus its CSS in the audited build. Its explicit budgets are 1 MiB JavaScript, 128 KiB per stylesheet, and 1.25 MiB total assets; gzip budgets are 256 KiB, 48 KiB, and 320 KiB respectively. These bounds leave measured headroom and remain enforced. The basic starter retains its smaller existing budgets. Choose the experimental DataViews variant for its interactions, with WordPress 7.1 or newer; do not describe that variant as the smallest or fastest option.
