# Dependency Maintenance

The inventory in [dependency-inventory.json](dependency-inventory.json) identifies
source pins, lockfiles, trust tiers, and update owners. A scheduled run is healthy
only when each dependency either reports that its supported pin is current or
produces a validated candidate PR. Review failed matrix instances every week;
a green schedule start alone is not evidence of successful maintenance.

## Review Policy

- Review high or critical advisories immediately and document reachability before
  considering an exception. Fix compatible versions first and exercise the affected
  build or runtime. Do not accept an advisory suppression simply because a package
  is a development dependency: parsers, downloaders, and build tools process inputs.
- Keep overrides narrow and versioned. Remove an override when the direct package
  supplies an equivalent patched graph. Major upgrades need a compatibility test,
  not an automatic acceptance of `npm audit fix --force` suggestions.
- For a blocked dependency, record the current pin, latest evaluated release,
  blocking reason, owner, next review date, and a link to the upstream issue in
  the update PR. Exceptions expire after 30 days unless renewed with new evidence.
- Publisher signature checks and reviewed metadata are distinct trust levels.
  Follow the [candidate isolation contract](update-model.md#candidate-isolation-and-recovery)
  for all external tools. Validate any changed upstream signing identity separately.
- Check supported releases at least weekly through Dependabot and the external
  updater. Security fixes should not wait for the normal weekly schedule.
- Audit all four npm lockfiles and both Python lockfiles under
  `tools/python-lint-tools/` and `tools/python-semgrep/`. Also audit fresh lint-only,
  Semgrep-only, and combined Python environments after hash-locked installation.
  The installer combines both Python locks in one environment; run `pip check`
  after both installs. File hashes establish artifact integrity, not absence of
  known vulnerabilities.

## Python Tool Lockfiles

Python lint and security tooling requires Python 3.10 or newer. Both input files
explicitly pin `pip` and `setuptools` so lint-only and security-only installations
also replace vulnerable interpreter-bundled packages. Regenerate each lock from its own tool
directory in an isolated compiler environment:

```bash
pip-compile --allow-unsafe --generate-hashes --output-file=requirements.txt requirements.in
```

The `--allow-unsafe` option includes the explicitly requested packaging tools in
the hash-locked output; it does not disable hash verification during installation.
Review every changed pin and retain `--require-hashes` when installing. Audit each
lock with `pip-audit -r requirements.txt`, then audit the packages actually
installed in each supported tool setup. Include supported Python versions in the
compatibility review: compiling on one interpreter does not establish compatibility
with older interpreters.

The Semgrep input bounds `rpds-py<2026` because its 2026 releases require Python
3.11, while 0.30.0 preserves the Python 3.10 floor. Revisit this bound when
intentionally raising that floor or if an advisory requires a newer release.

## Local Tool Installation

Tool selections are validated before the destination changes. A failed candidate
install leaves existing commands usable; partial selections preserve unrelated
commands. Python tool updates carry forward installed lint/security modes, and
`all` continues to leave Semgrep opt-in unless it is already installed.

The installer prepares immutable `.python-tools-venv.*` and `.node-tools.*`
directories, verifies them, then activates individual executable wrappers by
atomic rename. Physical environment paths never move because virtual-environment
scripts embed them. Previous successful environments remain available to running
processes; remove an unused old environment only after its processes finish and
no active wrapper references it. Failed candidate directories are removed.

## PHP Quality Tool Compatibility

The managed quality-tool manifest fixes Composer's resolution platform at PHP
8.0.0, the oldest supported interpreter for this tool bundle. Keep Composer's
runtime platform checks enabled. Installing with a newer Composer container must
not select dependencies that cannot execute under the supported host interpreter.
This tooling floor does not change a plugin's project-owned runtime metadata.

The reviewed lock uses Doctrine Instantiator 1.5.0, PHPStan 2.2.16,
phpstan-wordpress 2.0.4 and PHPUnit 9.6.37. Actual locked installation, platform
checks and quality-tool execution passed on PHP 8.0, including actual Doctrine object instantiation. The full foundation gate
also uses Composer's real solver to reject incompatible locked PHP requirements.

## September 25, 2026 Review

The four committed npm bundles were audited against the current npm advisory
service. Compatible fixes address `adm-zip` 0.6.1, `smol-toml` 1.7.1,
`js-yaml` 4.3.2, `svgo` 3.3.5, and `colord` 2.9.4. These replace vulnerable archive,
configuration, SVG, and color parsers. The `js-yaml`, `svgo` and `minimatch` overrides only target
the affected major series, preserving unrelated dependency API contracts. The
minimatch correction retains v3 callers while newer lint consumers receive the
v10 named-export API; a real typed-parser regression covers that boundary. All four
lockfile audits reported zero advisories after the fixes. This result is dated;
repeat audits because advisory data changes independently of source code.

The Python review also addressed all 24 then-open Dependabot advisories affecting
the Semgrep lock. Semgrep 1.163.0 constrained MCP and PyJWT to vulnerable versions,
so the scanner itself was upgraded to 1.178.0. Its compatible graph includes patched
AnyIO, Cryptography, MCP, Pydantic Settings, Starlette, Python Multipart, and PyJWT.
Both Python locks additionally pin pip 26.2 to address
[GHSA-wf93-45jw-7689](https://github.com/advisories/GHSA-wf93-45jw-7689) and
[GHSA-qwm4-qh6w-59xr](https://github.com/advisories/GHSA-qwm4-qh6w-59xr), which were
present in the interpreter-bundled installer. The follow-up review updates
Codespell to 2.4.3. Both locks also pin setuptools 83.0.0 to address
[GHSA-h35f-9h28-mq5c](https://github.com/advisories/GHSA-h35f-9h28-mq5c),
including the older setuptools seeded by Python 3.10 virtual environments.

Both Python lockfile audits and fresh lint-only, Semgrep-only, and combined
environment audits reported zero known vulnerabilities. Hash-locked installations
and `pip check` passed on Python 3.12; the combined installation also passed on
Python 3.14. The actual repository scanner detected all four expected rule IDs in
unsafe fixtures, accepted safe controls, and produced the expected SARIF on both
interpreters. The final combined locks and installer also passed on actual Python
3.10.21: 72 installed packages audited with zero advisories or skipped packages,
all four scanner rule IDs detected unsafe fixtures, and safe controls passed.
Re-run the supported tool bootstrap to apply these locks to an existing local
tool environment.

The external review evaluated and accepted these upstream releases:

| Dependency | Accepted pin | Review basis |
| --- | --- | --- |
| Plugin Check | 2.1.0 | Explicit major review of upstream release notes; existing reviewed author and stabilization period; WordPress readiness fixtures required |
| Plugin Update Checker | 5.7 | Same major; upstream source vendored unchanged; automatic-update metadata remains opt-in |
| EditorConfig Checker | 3.11.3 | Same major; platform archive hashes recorded and installer validation required |
| Syft | 1.52.0 | Exact publisher signature and signed checksum verification for every supported platform |
| Cosign | 3.1.3 | Exact publisher identity and valid Sigstore bundle for every supported platform |
| Composer | Official version 2 image digest | Docker registry digest recorded; compatible composer checks required |
| WordPress environment | 11.16.0 | Actual WordPress start, CLI execution, stop and owned environment cleanup |
| CodeQL Action | 4.38.2 | Official release commit, managed action catalog migration, workflow audit and parity |

ShellCheck 0.11.0, Actionlint 1.7.12, and Gitleaks 8.30.1 were already the latest
supported releases found by their handlers. Pinned versions need not track an
unrelated major release before its compatibility review is complete. No advisory
exception was required for the four audited npm bundles.

The DataViews starter required a deliberate upgrade from 14.3.0 to 19.1.0, with
its direct WordPress packages aligned to that release. The older package used a
private API opt-in removed from later WordPress dependency graphs: a successful
bundle did not prove it could render. The updated graph passes standalone browser
checks for search, sorting, pagination, page resets, and translated status filters,
plus a clean install, production build, JavaScript lint, and advisory audit. Verify
its generated asset dependencies and supported WordPress browser behavior whenever
updating this optional starter. See the admin pack migration instructions before
upgrading child-owned source.

The new artifact download action is pinned to the reviewed commit for 8.0.1,
which uses Node 24 and fails on archive digest mismatches. The updater additionally
checks its own candidate digest from trusted job outputs; neither check substitutes
for the other.

## Existing Child Projects

Admin source files, `package.json`, and `package-lock.json` are seeded once and
remain child-owned. A foundation update intentionally preserves them. Existing
children must review and merge corresponding manifest changes, regenerate their
own lockfile, run `npm ci`, `npm run build`, and `npm run lint:js`, and test the
rendered admin page. Preserve application-specific dependencies and source changes.
Do not replace a customized child lockfile with the foundation's starter lockfile.

New compatible security overrides can be copied from the matching starter
manifest and merged into the child's existing `overrides` object. Run
`npm install --package-lock-only --ignore-scripts`, review the diff, and audit the
result before installation. The effective admin tooling runtime floor is Node.js 22.22.2 or 24.15.0 in those
LTS series; Node.js 26 and newer also satisfy the declared engines. Align the
child manifest engines and CI runtime with the complete dependency graph.

Keep npm updates enabled for the child-owned package
through the managed Dependabot configuration. GitLab users should configure their
chosen dependency updater for the same child-owned paths.

## October 2026 tooling maintenance

WordPress environment tooling retains 11.16.0 and its Node 22-compatible
Playground graph, with `simple-git` 4.0.2
explicitly overridden until upstream adopts its security fixes. Version 4 removes
its default CommonJS export. The isolated installer applies the maintained
`scripts/lib/patch_wordpress_env_git.cjs` adaptation to the two upstream imports,
using the supported named export. It verifies exact package versions and both
upstream source SHA-256 digests before writing either file; drift aborts install.
No unsafe Git options or global module interception are introduced. Remove the
patch and override together when an upstream release supports patched simple-git.
The real wp-env download implementation is tested with clone, repeated fetch,
branch advancement and tag checkout, plus rejection of modified source files. The refreshed
lock also resolves patched `http-cache-semantics` and `proxy-addr` versions.
This removes the critical and high findings that previously stopped foundation
checks and unrelated dependency candidates. Keep the override scoped to this
isolated development tool; it does not change plugin runtime dependencies.
Qualify actual WordPress environment lifecycle behavior whenever updating it.

The advisory audit still reports moderate findings through upstream `js-yaml` 3
and its `argparse`/`sprintf-js` chain. There is no patched compatible `sprintf-js`
release at this review. Retain the existing high-severity failure threshold and
track upstream remediation; do not accept npm's suggested downgrade of the
WordPress environment tool to an obsolete major as a security fix. Tooling checks
now retain npm audit, install, and signature-verification diagnostics in CI logs,
so a future finding can be diagnosed without reproducing a silent failure.

Syft changed its publisher signature format to Sigstore bundles. Candidate
preparation verifies the bundle against the same exact release workflow identity
and OIDC issuer before accepting platform checksums. Missing bundles, invalid
signatures, or mismatched archive checksums still fail before pin mutation.

## Runtime-aligned major updates

The admin starters and existing-application fixture externalize React to
WordPress. WordPress 6.9 and 7.1.3 both publish React 18.3.1, so their development
React, React DOM and corresponding type packages must remain on the matching
major until the supported WordPress runtime is deliberately requalified. Dependabot
continues patch/minor checks; standalone React 19 proposals are excluded from
these three directories. Revisit all four packages together with that runtime
migration, rather than updating only React or React DOM.

The existing-application fixture retains TypeScript 6 because its pinned
`typescript-eslint` 8.70.0 parser supports `>=4.8.4 <6.1.0`. A TypeScript 7
upgrade must include a supported parser migration and full fixture qualification;
Dependabot continues compatible compiler updates while excluding standalone major
proposals for this fixture.

The Semgrep toolchain supports Python 3.10. Its existing `rpds-py<2026` constraint
is also represented in Dependabot configuration because the calendar-version
2026 releases require Python 3.11. Revisit the bound and automation policy together
when intentionally raising the Python support floor. These compatibility rules do
not suppress advisory scanning or permit vulnerable dependencies.

The October maintenance batch also advances the two hash-locked Python installer
pins to pip 26.2.1 and setuptools 84.0.0, and the Semgrep scanner to 1.179.0 with
its compatible PyJWT 2.15.1 dependency. The existing `rpds-py<2026` support bound
remains intact. Qualify the combined locks on the minimum Python 3.10 interpreter
and run the real scanner against unsafe fixtures before release.

The required full foundation CI job also installs the pinned scanner and runs
Semgrep's native rule tests against the actual production rule directory and
`tests/fixtures/semgrep/wordpress-security.php`. Every existing rule has an unsafe
case and a checked-permission control. This verifies detection behavior instead
of merely accepting a successful package install. The October local QEMU host
could install both supported Python graphs but could not execute either the
previous or updated scanner binary because its CPU ISA is below the binary's
requirement; scanner execution must pass on the supported CI runner before merge.
