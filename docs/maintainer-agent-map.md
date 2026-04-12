# Maintainer And Agent Map

This map is the quickest safe orientation for maintainers and AI coding agents working in this repository.

## Mission-Critical Entrypoints

- `scripts/foundation/validate.sh`: Primary foundation validation entrypoint.
- `scripts/foundation/validate-full.sh`: Full validation path that includes heavy fixture and release checks.
- `scripts/foundation/bootstrap_strict_local.sh`: Supported bootstrap path for strict-local parity from a clean clone.
- `scripts/update/sync_child_repo.sh`: Generates and synchronizes managed child-repo surfaces.
- `scripts/update/prepare_external_dependency_update.sh`: Shared external dependency update preparation logic used by updater automation.

## Generated Vs Owned Surfaces

Generated (do not hand-edit in child repos; edit templates/source here):

- `templates/child/.github/workflows/*`
- `templates/child/.github/dependabot.yml`
- `templates/child/.wp-plugin-base.env.example`
- `templates/child/CONTRIBUTING.md`
- `templates/child/*-pack/**` when matching pack gates are enabled

Owned in this repository (authoritative source):

- `scripts/**`
- `.github/workflows/**`
- `docs/**`
- `templates/**`

## Fast Path For Coding Agents

If you need to make a change quickly and safely, use this sequence:

1. identify the contract surface first (config, workflow, release script, managed template, docs, or fixtures)
2. edit authoritative source only (never hotfix generated child output)
3. run the narrowest relevant tests first
4. finish with at least `validate.sh --mode fast-local`

For any policy/release/dependency updater change, run `validate-full.sh --mode ci` before merge.

## Change Recipes

### 1) Add or change a config key

Update all four surfaces together:

- `scripts/lib/load_config.sh`
- `docs/config-schema.json`
- `README.md` config section
- `templates/child/.wp-plugin-base.env.example`

Then run:

- `bash scripts/ci/validate_config_contract.sh`

### 2) Change managed release/update workflows

Keep reusable/root workflow and child template in lockstep:

- `.github/workflows/*`
- `templates/child/.github/workflows/*`

Then run:

- `bash scripts/foundation/test_workflow_parity.sh`
- `bash scripts/foundation/validate.sh --mode fast-local` (this runs foundation contract assertions with the required fixture inputs)

### 3) Change release/distribution channel behavior

Touch all relevant surfaces:

- release workflow(s)
- release script(s) in `scripts/release/`
- docs (`README.md`, `docs/release-model.md`, channel docs)
- security host policy (`scripts/ci/audit_workflows.sh`, `docs/security-model.md`) if network calls changed
- fixtures (`scripts/foundation/run_release_update_fixture_checks.sh`)

Then run:

- `bash scripts/foundation/run_release_update_fixture_checks.sh "$PWD"`

### 4) Change external dependency updater behavior

Touch all relevant surfaces:

- `.github/workflows/update-plugin-check.yml`
- `scripts/update/prepare_external_dependency_update.sh`
- `docs/dependency-inventory.json`
- `docs/update-model.md`

Then run:

- `bash scripts/ci/validate_dependency_inventory.sh`
- `bash scripts/foundation/test_dependency_inventory.sh`
- `bash scripts/ci/audit_workflows.sh`

## Validation Commands

- Fast local: `bash scripts/foundation/validate.sh --mode fast-local`
- Strict local: `bash scripts/foundation/validate.sh --mode strict-local`
- Full CI-equivalent path: `bash scripts/foundation/validate-full.sh --mode ci`

If strict-local fails on missing tools, bootstrap first:

- `bash scripts/foundation/bootstrap_strict_local.sh "$HOME/.local/wp-plugin-base-tools"`

## High-Risk Change Areas

- `scripts/ci/audit_workflows.sh`: Security policy gate for workflows/actions/permissions.
- `scripts/update/create_or_update_pr.sh`: Privileged branch/push/PR automation.
- `scripts/release/*`: Release publication and provenance verification.
- `scripts/lib/load_config.sh`: Canonical config-loading and defaults behavior.
- `templates/child/.github/workflows/*`: Managed runtime automation projected into child repos.

## Required Safety Checks Before Merge

1. Run foundation validation in at least `fast-local` mode.
2. When changing policy or update automation, run `validate-full.sh --mode ci`.
3. Keep `docs/config-schema.json`, `README.md` config keys, and `load_config.sh` behavior in sync.
4. Keep reusable and child workflow parity tests passing.
5. Keep docs consistent with behavior changes (especially release ordering, channel defaults, and updater scope).
