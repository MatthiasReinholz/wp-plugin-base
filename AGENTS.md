# Agent Operating Contract

This repository is the authoritative `wp-plugin-base` foundation. Start technical changes by reading `docs/maintainer-agent-map.md`, then edit the source surface named there instead of patching generated output.

## Source Of Truth

- Framework behavior lives under `scripts/`, `.github/workflows/`, `docs/`, and `templates/child/`.
- Child project output is generated from `templates/child/` by `scripts/update/sync_child_repo.sh`.
- Do not hotfix generated child files directly when the change belongs in the foundation template or script.
- If a config key changes, update `scripts/lib/load_config.sh`, `scripts/ci/validate_config.sh`, `docs/config-schema.json`, `README.md`, and `templates/child/.wp-plugin-base.env.example` together.
- If a managed file is added or removed, update `scripts/lib/managed_files.sh`, `docs/managed-files.md`, sync validation, and package exclusions when the file is not runtime code.

## Validation

Run focused tests for the touched surface, then run:

```bash
bash scripts/foundation/validate.sh --mode fast-local
```

For release, update, workflow, packaging, or provenance changes, also run:

```bash
bash scripts/ci/audit_workflows.sh .
bash scripts/foundation/test_workflow_parity.sh
bash scripts/foundation/run_release_update_fixture_checks.sh "$PWD"
```

For config/runtime pack changes, also run:

```bash
bash scripts/foundation/test_validate_config_runtime_pack_contracts.sh
bash scripts/foundation/test_rest_operations_pack_contracts.sh
```

Use `bash scripts/foundation/bootstrap_strict_local.sh "$PWD/.wp-plugin-base-tools"` and `bash scripts/foundation/validate.sh --mode strict-local` before release when local lint/security tools are expected.

## Security Rules

- Keep release and update paths fail closed. Do not bypass tag, provenance, draft, asset, or permission checks to make a workflow pass.
- Public WordPress endpoints require exact suppressions with `kind`, `identifier`, repo-relative `path`, and a non-empty justification copied from scanner output.
- Prefer fixing upstream managed foundation code over patching downstream projects when the dependency is owned here.
- Do not persist GitHub tokens in git remotes, `url.insteadOf`, process arguments, or local git config.
