# REST Operations Pack

Enable `REST_OPERATIONS_PACK_ENABLED=true` to sync the managed REST operations bootstrap into your project.

`REST_API_NAMESPACE` defaults to `<plugin-slug>/v1`, derived from `PLUGIN_SLUG`. Override it only when the child plugin needs a non-default namespace contract.

This pack uses a hybrid ownership model:

- managed under `lib/wp-plugin-base/rest-operations/`
- child-owned under `includes/rest-operations/`

## Required Main Plugin Include

Add this line to your plugin main file:

```php
require_once __DIR__ . '/lib/wp-plugin-base/rest-operations/bootstrap.php';
```

## Operation Model

Your child-owned `includes/rest-operations/bootstrap.php` file must return an array of operation manifests. The canonical manifest contract is tracked in `docs/rest-operation-manifest-contract.json`, and foundation validation enforces the generated bootstrap against that contract.

Each operation manifest should declare:

- `id`
- `route`
- `methods`
- `callback` (string callable or static callable array)
- `visibility`
- `required_scopes`
- `capability` or `capability_callback` for non-public operations
- optional `input_schema`
- optional `output_schema`
- optional `annotations`
- optional `ability`
- optional `source_file` (the seed bootstrap sets this automatically for review and suppressions)

## Visibility

Supported `visibility` values:

- `public`
- `authenticated`
- `admin`

Public operations must also declare a justified `rest_public_operation` suppression in the configured security suppressions file.

If you need to keep a project-owned direct `register_rest_route()` during migration, add a justified `rest_route_bypass` suppression keyed to that file path. The managed contract remains registry-first, but coexistence is explicit and auditable.

## Scope Resolution

The managed evaluator keeps capability checks mandatory and then applies scope narrowing:

- administrators receive wildcard scope access by default
- user meta can supply additional scopes through `<plugin_slug>_rest_operation_scopes`
- plugins can override or augment grants through the `<plugin_slug>_rest_granted_scopes` filter

## Abilities

Set `REST_ABILITIES_ENABLED=true` to expose operations through the Abilities API when WordPress 6.9+ is available. The operation manifest is ability-ready from the first release, even when REST remains the primary transport.

Disabling `REST_OPERATIONS_PACK_ENABLED` is also a manual reconciliation step. Sync removes the managed bootstrap, but it does not rewrite child-owned plugin entrypoints or seeded operation files. Remove the `require_once __DIR__ . '/lib/wp-plugin-base/rest-operations/bootstrap.php';` line from the main plugin file before validation or packaging will pass.
