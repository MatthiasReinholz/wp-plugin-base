# Product Layers

`wp-plugin-base` currently owns **Layer 1** of a broader plugin engineering platform.

## Layer 1: Delivery Foundation

This repository provides:

- managed local workflows
- release and packaging automation
- optional WordPress.org deployment
- workflow hardening and provenance checks
- vendored scripts, templates, and docs inside `.wp-plugin-base/`

This is the stable layer existing adopters rely on today.

## Layer 2: Runtime Starter

This layer does not exist in this repository today.

If it is added later, it should be a separate companion layer or package covering plugin runtime concerns such as:

- Composer and PSR-4 scaffolding
- PHPCS, PHPStan, and PHPUnit setup
- secure runtime plugin patterns
- settings, REST, or block examples

Keeping runtime concerns separate preserves backward compatibility for repositories that only want the delivery foundation.

## Layer 3: Optional Packs

Future opt-in modules can sit above the foundation, for example:

- quality packs for child repos
- example plugin repos
- WordPress.org deployment presets
- WooCommerce-oriented runtime starters

Those modules should remain additive and should not change the Layer 1 contract without a major version.
