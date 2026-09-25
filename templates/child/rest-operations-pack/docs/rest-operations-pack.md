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
- optional `error_response`
- optional `source_file` (the seed bootstrap sets this automatically for review and suppressions)

## Input Schema Contract

Operation inputs use an object schema and WordPress' supported REST JSON Schema keywords. Both transports validate the complete object, including `required`, `additionalProperties`, property-count constraints, and nested object constraints, before calling the operation. Unsupported JSON Schema keywords do not gain enforcement from this pack.

Defaults for missing top-level properties are applied after raw input validation. A default does not satisfy a required property or `minProperties`; pass required data explicitly. Nested defaults are not materialized. Use the same complete object when calling an ability directly, for example `$ability->execute( array( 'message' => 'Hello' ) )`.

Required properties enforce presence: an explicit `null` is accepted only when the property's schema permits it. Both transports validate the final sanitized input and applied defaults again before permissions or execution, so normalization cannot produce a value outside the schema. Invalid capability metadata fails closed at runtime, including operations registered programmatically.

REST transport controls (`_fields`, `_embed`, `_envelope`, `_locale`, `_method`, `_jsonp`, `_wpnonce`, and `rest_route`) are excluded from schema validation unless explicitly declared in `properties`. Other unknown fields are rejected when `additionalProperties` is false. Schema failures return HTTP 400. WordPress continues to handle per-field REST validation and sanitization before the managed callback.

## Visibility

Supported `visibility` values:

- `public`
- `authenticated`
- `admin`

Public operations must also declare a justified `rest_public_operation` suppression in the configured security suppressions file.

If you need to keep a project-owned direct `register_rest_route()` during migration, add a justified `rest_route_bypass` suppression keyed to that file path. The managed contract remains registry-first, but coexistence is explicit and auditable.

## Error Responses

By default, managed REST operations preserve WordPress `WP_Error` compatibility. Operations that need a stable client-facing shape for callback and execution errors can opt in per operation:

```php
'error_response' => array(
    'mode'    => 'envelope',
    'message' => __( 'The request could not be completed.', '__PLUGIN_SLUG__' ),
),
```

Opted-in callback error responses use an `error` envelope with the WordPress error code, a safe public message, the HTTP status, and generated or forwarded `request_id` / `correlation_id` values. The same id is also sent in `X-Request-ID` and `X-Correlation-ID` headers when the REST response object supports headers.

The envelope intentionally does not expose raw exception messages, provider credentials, authorization headers, or upstream response bodies. If `message` is omitted, the managed generic error message is used.

Authorization, capability, and scope failures still flow through WordPress' native REST permission pipeline so permission-check ordering and default `WP_Error` compatibility remain unchanged.

## Scope Resolution

The managed evaluator keeps capability checks mandatory and then applies scope narrowing:

- administrators receive wildcard scope access by default
- user meta can supply additional scopes through `<plugin_slug>_rest_operation_scopes`
- plugins can override or augment grants through the `<plugin_slug>_rest_granted_scopes` filter

## Abilities

Set `REST_ABILITIES_ENABLED=true` to expose operations through the Abilities API when WordPress 6.9+ is available. The operation manifest is ability-ready from the first release, even when REST remains the primary transport.

Abilities use the same capability and scope evaluator as REST through core's required `permission_callback`. Manifest `annotations` and `ability.show_in_rest` are mapped into the core ability's `meta`. Abilities remain hidden from the core Abilities REST API unless `show_in_rest` is explicitly true; enabling exposure does not bypass authorization. Core validates declared ability output schemas. Registration failures emit a developer diagnostic.

Upgrading the foundation refreshes this managed adapter automatically. Existing operation manifests remain child-owned: review schemas for callers that previously sent undeclared fields or relied on defaults satisfying required fields before deploying the stricter validation.

Disabling `REST_OPERATIONS_PACK_ENABLED` is also a manual reconciliation step. Sync removes the managed bootstrap, but it does not rewrite child-owned plugin entrypoints or seeded operation files. Remove the `require_once __DIR__ . '/lib/wp-plugin-base/rest-operations/bootstrap.php';` line from the main plugin file before validation or packaging will pass.
