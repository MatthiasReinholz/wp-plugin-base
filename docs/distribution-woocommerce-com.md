# WooCommerce.com Marketplace Distribution

WooCommerce.com distribution is an opt-in channel and is disabled by default.

## Enablement

Set this CI variable on the selected host:

- `WOOCOMMERCE_COM_DEPLOY_ENABLED=true`

Set these protected deployment secrets on the selected host:

- `WOO_COM_USERNAME`
- `WOO_COM_APP_PASSWORD` (WordPress application password)

Set this project config key in `.wp-plugin-base.env`:

- `WOOCOMMERCE_COM_PRODUCT_ID=<numeric product id>`
- `WOOCOMMERCE_COM_ENDPOINT_TIMEOUT_SECONDS=30` (optional, defaults to 30 seconds)

## Channel Behavior

During `finalize-release` and `release` workflows:

1. `validate_woocommerce_com_deploy.sh` checks credentials, product ID, Woo header parity, package version, and ZIP integrity.
2. `deploy_woocommerce_com.sh` checks the Woo submission-runner status endpoint, blocks on in-flight conflicting deployments, and uploads the release ZIP via multipart form fields.
3. The deploy call is queue-and-exit: the workflow does not block for long Woo QIT completion polling.

If `WOOCOMMERCE_COM_PRODUCT_ID` is empty, validation soft-skips with a warning so onboarding repositories are not blocked during vendor approval.

## Release-Order Interaction

The selected Git host tag + release are published first, then channel deploy steps run.

A Woo or WordPress.org channel failure can happen after host-release publication. The workflow is still marked failed so operators can repair channels without losing visibility.

## Repair Runbook

- GitHub:
  - run manual `release.yml` for the existing tag
  - run manual `woocommerce-status.yml` to inspect channel state
- GitLab:
  - rerun the tagged `release` job from the managed `.gitlab-ci.yml` for the existing tag
  - inspect Woo vendor/QIT status directly because there is no separate `woocommerce-status.yml` workflow
- If Woo reports an in-flight deployment, wait and re-check status.
- If Woo reports failed or idle with the target version missing, rerun the same host-specific repair path and verify status again.

## Woo Header Contract

The packaged main plugin file must include a valid Woo header:

- `Woo: <product_id>:<hash>`

The `<product_id>` must match `WOOCOMMERCE_COM_PRODUCT_ID`.

There is intentionally no config escape hatch to disable Woo header validation. The channel contract requires the approved Woo header before upload.

## Application Password Setup

Generate the Woo deployment credential as a WordPress Application Password in your Woo vendor account settings, then store it in `WOO_COM_APP_PASSWORD` as a protected deployment secret on the selected host. Do not use your interactive account password.

## QIT Failure Handling

Queue-and-exit means failures can occur asynchronously after upload. On GitHub, use `woocommerce-status.yml` to inspect state. On GitLab, inspect the Woo vendor/QIT status directly:

- `running` or `queued`: wait, then rerun status.
- `failed`: inspect Woo/QIT error details in vendor tooling, fix the package, and rerun the same host-specific release repair path for the same tag.
- `idle`/missing target version: rerun the same host-specific release repair path and verify status again.

## References

- [Woo vendor signup](https://woocommerce.com/vendor-signup/)
- [Security model](security-model.md)
- [Release model](release-model.md)
