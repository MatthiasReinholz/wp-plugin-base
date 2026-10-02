<?php
/** Build isolated Plugin Check dependencies from exact WordPress.org release pins. */
declare(strict_types=1);

try {
    $raw = $argv[1] ?? '';
    $plugins = [];
    $slugs = [];
    foreach ($raw === '' ? [] : explode(',', $raw) as $dependency) {
        if (!preg_match('/\A([a-z0-9]+(?:-[a-z0-9]+)*)@([0-9]+(?:\.[0-9]+)+)\z/', $dependency, $match)) {
            throw new InvalidArgumentException('WORDPRESS_TEST_PLUGINS requires comma-separated slug@exact.version entries.');
        }
        if (isset($slugs[$match[1]])) {
            throw new InvalidArgumentException('WORDPRESS_TEST_PLUGINS contains a duplicate plugin slug.');
        }
        $slugs[$match[1]] = true;
        $plugins[] = 'https://downloads.wordpress.org/plugin/' . $match[1] . '.' . $match[2] . '.zip';
    }
    if (isset($argv[2])) {
        $plugins[] = $argv[2];
        $output = [
            'plugins' => $plugins,
            'port' => (int) ($argv[3] ?? 0),
            'testsPort' => (int) ($argv[4] ?? 0),
            'testsEnvironment' => false,
        ];
    } else {
        $output = $plugins;
    }
    echo json_encode($output, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . PHP_EOL;
} catch (InvalidArgumentException $exception) {
    fwrite(STDERR, $exception->getMessage() . PHP_EOL);
    exit(1);
}
