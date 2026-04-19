# Product Layers

`wp-plugin-base` currently owns **Layer 1** of a broader plugin engineering platform.

## Layer 1: Delivery Foundation

This repository provides:

- managed local automation scaffolding
- release and packaging automation
- optional WordPress.org and WooCommerce.com distribution channels
- workflow hardening and provenance checks
- vendored scripts, templates, and docs inside `.wp-plugin-base/`

This is the stable layer existing adopters rely on today.

## Layer 2: Runtime Packs (Opt-In)

Layer 2 is now an explicit opt-in surface for narrowly scoped runtime features.

Current Layer 2 pack in this repository:

- provider-based runtime updater pack (`PLUGIN_RUNTIME_UPDATE_PROVIDER!=none`)
- REST operations pack (`REST_OPERATIONS_PACK_ENABLED=true`)
- Admin UI pack (`ADMIN_UI_PACK_ENABLED=true`)

Reference:

- [Runtime In-Dashboard Updater](distribution-runtime-updater.md)

Layer 2 remains additive and disabled by default. It must not change Layer 1 release/delivery behavior unless explicitly enabled per project.

Release/distribution channel behavior for Layer 1 is documented in:

- [Release model](release-model.md)
- [WooCommerce.com distribution](distribution-woocommerce-com.md)

Future Layer 2 additions should stay constrained to optional runtime concerns such as:

- Composer and PSR-4 scaffolding
- secure runtime plugin patterns
- abilities adapters or companion-runtime extraction
- block or modern UI flavors that stay additive

## Layer 3: Optional Packs

Future opt-in modules can sit above the foundation, for example:

- quality packs for child repos
- example plugin repos
- WordPress.org deployment presets
- WooCommerce-oriented runtime starters

Those modules should remain additive and should not change the Layer 1 contract without a major version.
