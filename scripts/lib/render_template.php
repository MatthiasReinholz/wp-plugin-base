<?php
/**
 * Render foundation placeholders without injecting configuration into source code.
 *
 * PHP placeholders must occur in constant string literals or comments. JavaScript
 * placeholders use JSON string escaping; YAML values use quoted JSON scalars.
 * Replacement is one pass, so a value containing another marker stays literal.
 */
declare(strict_types=1);

$source = $argv[1] ?? '';
$content = file_get_contents($source);
if (false === $content) {
    throw new RuntimeException('Cannot read template: ' . $source);
}
$keys = explode(' ', 'FOUNDATION_REPOSITORY FOUNDATION_RELEASE_SOURCE_PROVIDER FOUNDATION_RELEASE_SOURCE_REFERENCE FOUNDATION_RELEASE_SOURCE_API_BASE FOUNDATION_VERSION PRODUCTION_ENVIRONMENT CODEOWNERS_REVIEWERS PLUGIN_NAME PLUGIN_SLUG MAIN_PLUGIN_FILE README_FILE ZIP_FILE PHP_VERSION NODE_VERSION VERSION_CONSTANT_NAME DISTIGNORE_FILE WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE GITHUB_RELEASE_UPDATER_REPO_URL PLUGIN_RUNTIME_UPDATE_PROVIDER PLUGIN_RUNTIME_UPDATE_SOURCE_URL AUTOMATION_PROVIDER REST_API_NAMESPACE REST_ABILITIES_ENABLED ADMIN_UI_EXPERIMENTAL_DATAVIEWS');
$values = array();
foreach ($keys as $key) {
    $value = getenv($key);
    $values['__' . $key . '__'] = false === $value ? '' : $value;
}
// The optional child ruleset is a fixed authored include, never configuration XML.
$values['__PHPCS_CHILD_RULE__'] = 'true' === getenv('WP_PLUGIN_BASE_PHPCS_CHILD_RULE')
    ? '  <rule ref=".wp-plugin-base-quality-pack/phpcs-child.xml"/>' : '';
$replace = static function (string $text, callable $encode) use ($values): string {
    return preg_replace_callback('/__(' . implode('|', array_map(static fn($key) => substr($key, 2, -2), array_keys($values))) . ')__/', static fn($match) => $encode($values[$match[0]]), $text);
};
$identity = static fn(string $value): string => $value;
$json = static fn(string $value): string => json_encode($value, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES);

// This restricted Git ref is used inside authored quoted shell/YAML literals
// and exact GitHub expressions. Validate independently before raw substitution.
if (str_contains($content, '__DEFAULT_BRANCH__')) {
    $branch = getenv('DEFAULT_BRANCH');
    $branch = (false === $branch || '' === $branch) ? 'main' : $branch;
    if ('HEAD' === $branch || !preg_match('~^[A-Za-z0-9][A-Za-z0-9._/-]*$~D', $branch)
        || str_contains($branch, '..') || str_contains($branch, '//')
        || preg_match('~(^|/)(refs|pull)(/|$)|(^|/)\\.|\\.lock(/|$)|[/.]$~', $branch)) {
        throw new RuntimeException('Unsafe default branch in template rendering.');
    }
    $content = str_replace('__DEFAULT_BRANCH__', $branch, $content);
}

// Rename authored runtime symbols before inserting configuration, so a plugin
// display name containing a framework-like identifier remains literal data.
if ('true' === getenv('WP_PLUGIN_BASE_RUNTIME_TEMPLATE') && '' !== (string) getenv('RUNTIME_CLASS_PREFIX')) {
    $prefix = getenv('RUNTIME_CLASS_PREFIX');
    $content = preg_replace('/\bWP_Plugin_Base_/', $prefix . 'WP_Plugin_Base_', $content);
    $content = preg_replace('/\bwp_plugin_base_example_/', strtolower($prefix) . 'wp_plugin_base_example_', $content);
}
if (preg_match('/\.php(?:\.example)?$/', $source)) {
    $output = '';
    foreach (token_get_all($content) as $token) {
        if (!is_array($token)) {
            $output .= $token;
            continue;
        }
        [$kind, $text] = $token;
        if (T_CONSTANT_ENCAPSED_STRING === $kind && str_contains($text, '__')) {
            // All authored PHP template strings are single quoted. Refuse a new
            // interpolating context until its encoding is explicitly supported.
            if ("'" !== $text[0]) {
                foreach (array_keys($values) as $marker) {
                    if (str_contains($text, $marker)) {
                        throw new RuntimeException('PHP placeholders require single-quoted literals: ' . $source);
                    }
                }
            } else {
                $literal = str_replace(array("\\'", '\\\\'), array("'", '\\'), substr($text, 1, -1));
                $text = var_export($replace($literal, $identity), true);
            }
        } elseif (in_array($kind, array(T_COMMENT, T_DOC_COMMENT), true)) {
            $text = $replace($text, static fn(string $value): string => str_replace('*/', '* /', $value));
        } else {
            foreach (array_keys($values) as $marker) {
                if (str_contains($text, $marker)) {
                    throw new RuntimeException('Unsupported PHP placeholder context: ' . $source);
                }
            }
        }
        $output .= $text;
    }
    $content = $output;
} elseif (preg_match('/\.(js|json)$/', $source)) {
    // Encode for the actual quote delimiter, including WordPress-style JS
    // single quotes. Keep existing escapes in the authored template intact.
    $content = preg_replace_callback('/\'(?:\\\\.|[^\'\\\\])*\'|"(?:\\\\.|[^"\\\\])*"/s', static function (array $match) use ($replace, $json): string {
        $quote = $match[0][0];
        $body = $replace(substr($match[0], 1, -1), static function (string $value) use ($quote, $json): string {
            $escaped = substr($json($value), 1, -1);
            return "'" === $quote ? str_replace("'", "\\'", $escaped) : $escaped;
        });
        return $quote . $body . $quote;
    }, $content);
} elseif (preg_match('/\.ya?ml$/', $source)) {
    $content = $replace($content, $json);
} else {
    $content = $replace($content, $identity);
}

echo $content;
