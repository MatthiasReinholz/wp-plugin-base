#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
wp_plugin_base_load_config "${1:-}"
export PHP_RUNTIME_MATRIX PHP_VERSION
php <<'PHP'
<?php
$versions = array_filter(explode(',', getenv('PHP_RUNTIME_MATRIX') ?: ''));
$images = json_decode(getenv('WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGES') ?: '{}', true, 512, JSON_THROW_ON_ERROR);
if (!is_array($images)) throw new RuntimeException('Runtime image map must be a JSON object.');
echo "stages: [test]\n";
if (!$versions) {
    $image = getenv('WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGE');
    if (!is_string($image) || !preg_match('/^[A-Za-z0-9.\/:_-]+@sha256:[a-f0-9]{64}$/', $image)) {
        throw new RuntimeException('Disabled matrix still requires a pinned default runner image.');
    }
    echo "runtime-matrix-disabled:\n  stage: test\n  image: " . json_encode($image) . "\n  script: ['echo PHP_RUNTIME_MATRIX is not configured']\n";
}
foreach (array_unique($versions) as $version) {
    if (!preg_match('/^[0-9]+(?:\.[0-9]+){0,2}$/', $version)) throw new RuntimeException('Invalid PHP runtime version.');
    $image = $images[$version] ?? null;
    if (!is_string($image) || !preg_match('/^[A-Za-z0-9.\/:_-]+@sha256:[a-f0-9]{64}$/', $image)) {
        throw new RuntimeException('WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGES must map PHP ' . $version . ' to a provisioned digest-pinned image.');
    }
    echo json_encode('runtime-php-' . $version) . ":\n  stage: test\n  image: " . json_encode($image) . "\n";
    echo "  variables:\n    WP_PLUGIN_BASE_GITLAB_BOOTSTRAP_APT: 'false'\n    WP_PLUGIN_BASE_EXPECTED_PHP_VERSION: " . json_encode($version) . "\n    WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGE: " . json_encode($image) . "\n";
    echo "  script:\n    - bash .wp-plugin-base/scripts/ci/prepare_gitlab_runtime.sh .wp-plugin-base.env\n    - bash .wp-plugin-base/scripts/ci/run_php_runtime_smoke.sh .wp-plugin-base.env\n";
}
PHP
