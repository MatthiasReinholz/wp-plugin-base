# Maintainer And Agent Map

This map is the quickest safe orientation for maintainers and AI coding agents working in this repository.

## Control Plane Entrypoints

- `scripts/foundation/validate.sh`: Primary foundation validation entrypoint.
- `scripts/foundation/validate-full.sh`: Full validation path that includes heavy fixture and release checks.
- `scripts/foundation/bootstrap_strict_local.sh`: Supported bootstrap path for strict-local parity from a clean clone.
- `scripts/update/sync_child_repo.sh`: Generates and synchronizes managed child-repo surfaces.

## Generated Vs Owned Surfaces

Generated (do not hand-edit in child repos; edit templates/source here):

- `templates/child/.github/workflows/*`
- `templates/child/.github/dependabot.yml`
- `templates/child/.wp-plugin-base.env.example`
- `templates/child/CONTRIBUTING.md`

Owned in this repository (authoritative source):

- `scripts/**`
- `.github/workflows/**`
- `docs/**`
- `templates/**`

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

- Run foundation validation in at least `fast-local` mode.
- When changing policy or update automation, run `strict-local` or CI.
- Keep `docs/config-schema.json`, `README.md` config keys, and `load_config.sh` behavior in sync.
- Keep reusable and child workflow parity tests passing.
