<?php
/**
 * Reconstruct the published v1.8.3 placeholder format as inert comparison data.
 *
 * The caller may use this candidate only for exact existing hosted-file ownership
 * proof. Normal generation must use render_template.php and the current action
 * catalog. Do not evaluate or include code from a historical foundation checkout.
 * The fixed order mirrors the published renderer's serial raw substitutions.
 */
declare(strict_types=1);

// Reviewed tracked hosted-template blobs from v1.8.3, commit
// 58a1aa68acababb303eea6760923c60cbf648f10. Keep runtime trust data independent
// from test fixtures. Qualify the complete set: some authored templates did not
// change in later releases, so a single matching file cannot identify this era.
$templates = array(
    '.github/CODEOWNERS' => '0f81a647d5ee7df76e5a8c207c28ae354b840d0a15a89c06905e0d7555204a45',
    '.github/dependabot.yml' => '89b0ac216125cd11a5806de70472a5d4cb470a2143606d62a03993e13e6dd02e',
    '.github/workflows/ci.yml' => '832ee5b296c3ff9b861866f0c730fa20373d67db5a3f1e614e7c7942aa4eaac7',
    '.github/workflows/finalize-release.yml' => '6b691999a87811ac5af14bc29aac8d4188a167520651b8c7ed44e16095e0fd4a',
    '.github/workflows/prepare-release.yml' => '8d3b32ae677dcf8b922658a4228e11d07bf82930f288fc17fd8d4b25d3fe752c',
    '.github/workflows/publish-tag-release.yml' => '9f946f3de5614bed7fb8aaaea2e5236dda432f4a60a3d89e41125e7d25595549',
    '.github/workflows/release.yml' => '1369fca421b11ec34087eaed388bba7a4de3126deb6eb1aff23dae4e0f833c19',
    '.github/workflows/simulate-release.yml' => 'fdbefd8f22b6d893ad6565736b22d33fbac064f542829e1519d1edaa1c1ae51b',
    '.github/workflows/update-foundation.yml' => '83b8e8a20ef7dae3cb45e6ddf0f28b904da0d8868098819a2beae343fe6832bf',
    '.github/workflows/woocommerce-status.yml' => 'fe133c5f87f0f7390d960fab1d9c5659d2e28e25ad9792b9a47158b74f873fbb',
    '.gitlab-ci.yml' => '35756e5ee30242ac07943295fa75ca7b1e0a8c5fb98b2bed93d99ef8a04fffcc',
    '.gitlab/CODEOWNERS' => 'c785957f8d7c567b83c223ba7e5c8c182018bcd81fbaf84de43632f613695fb6',
    'qit-pack/.github/workflows/woocommerce-qit.yml' => '39df20c52cdd8f8310e300b092f660118f8eaf9f41175b28a84865b36db599e9',
);
if ('v1.8.3' !== getenv('FOUNDATION_VERSION')) {
    exit(2);
}
$source = $argv[1] ?? '';
$directory = rtrim($argv[2] ?? '', '/');
if ('--qualify' === $source) {
    foreach ($templates as $name => $digest) {
        $path = $directory . '/' . $name;
        if (!is_file($path) || hash_file('sha256', $path) !== $digest) {
            exit(2);
        }
    }
    exit(0);
}
$prefix = $directory . '/';
$name = str_starts_with($source, $prefix) ? substr($source, strlen($prefix)) : '';
if (!isset($templates[$name]) || !is_file($source)) {
    exit(2);
}
$content = file_get_contents($source);
if (false === $content) {
    throw new RuntimeException('Cannot read historical automation template: ' . $source);
}
// Recheck the selected blob after qualification in case it changed in between.
if (hash('sha256', $content) !== $templates[$name]) {
    exit(2);
}
$keys = explode(' ', 'FOUNDATION_REPOSITORY FOUNDATION_RELEASE_SOURCE_PROVIDER FOUNDATION_RELEASE_SOURCE_REFERENCE FOUNDATION_RELEASE_SOURCE_API_BASE FOUNDATION_VERSION PRODUCTION_ENVIRONMENT CODEOWNERS_REVIEWERS PLUGIN_NAME PLUGIN_SLUG MAIN_PLUGIN_FILE README_FILE ZIP_FILE PHP_VERSION NODE_VERSION VERSION_CONSTANT_NAME DISTIGNORE_FILE WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE GITHUB_RELEASE_UPDATER_REPO_URL PLUGIN_RUNTIME_UPDATE_PROVIDER PLUGIN_RUNTIME_UPDATE_SOURCE_URL AUTOMATION_PROVIDER REST_API_NAMESPACE REST_ABILITIES_ENABLED ADMIN_UI_EXPERIMENTAL_DATAVIEWS');
foreach ($keys as $key) {
    $value = getenv($key);
    $content = str_replace('__' . $key . '__', false === $value ? '' : $value, $content);
}
echo $content;
