#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
cp -R "$ROOT_DIR/tests/fixtures/runtime-pack-ready/." "$fixture/"
mkdir -p "$fixture/.wp-plugin-base"
rsync -a --exclude .git "$ROOT_DIR/" "$fixture/.wp-plugin-base/"
# Exercise first-generation isolation (the compatibility fixture opts out).
sed '/^RUNTIME_CLASS_PREFIX=/d' "$fixture/.wp-plugin-base.env" > "$fixture/config.tmp"
mv "$fixture/config.tmp" "$fixture/.wp-plugin-base.env"
cat >> "$fixture/.wp-plugin-base.env" <<'EOF'
PLUGIN_NAME="Owner's \\Path \"Plugin\" ${literal} __PLUGIN_SLUG__"
SIMULATE_RELEASE_WORKFLOW_ENABLED=true
WOOCOMMERCE_QIT_ENABLED=true
WOOCOMMERCE_COM_PRODUCT_ID=123
EOF
sync_fixture() {
  WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh" >/dev/null
}
sync_fixture
# Replacing only the managed range preserves child-owned bytes on both sides,
# including mixed line endings and a suffix without a final newline.
FIXTURE="$fixture" php <<'PHP'
<?php
$path = getenv('FIXTURE') . '/AGENTS.md';
$managed = file_get_contents($path);
$prefix = "# Child instructions\r\nKeep the owner's literal \$value.\r\n\r\n";
$suffix = "\n\n## Child footer\nPreserve this final line without a newline.";
$expected = $prefix . $managed . $suffix;
file_put_contents($path, $expected);
file_put_contents(getenv('FIXTURE') . '/agents.expected', $expected);
PHP
sync_fixture
cmp "$fixture/agents.expected" "$fixture/AGENTS.md"
sync_fixture
cmp "$fixture/agents.expected" "$fixture/AGENTS.md"
prefix="$(sed -n 's/^RUNTIME_CLASS_PREFIX=//p' "$fixture/.wp-plugin-base.env")"
[[ "$prefix" == Wpb_runtime_pack_ready_*_ ]]
test -f "$fixture/.github/workflows/simulate-release.yml"
ruby -ryaml -e 'job = YAML.load_file(ARGV[0]).fetch("jobs").fetch("qit"); php = job.fetch("steps").find { |step| step["uses"].to_s.start_with?("shivammathur/setup-php@") }; abort "Quoted PHP placeholder was double-encoded" unless php.fetch("with").fetch("php-version") == "8.1"; run = job.fetch("steps").last; abort "QIT input interpolated into shell source" if run.fetch("run").include?("${{"); abort "QIT inputs missing" unless run.fetch("env").keys.include?("EXTENSION_SLUG")' "$fixture/.github/workflows/woocommerce-qit.yml"

test -f "$fixture/.github/workflows/woocommerce-status.yml"
grep -Fq 'directory: /.wp-plugin-base-admin-ui' "$fixture/.github/dependabot.yml"
find "$fixture/lib" "$fixture/includes" -name '*.php' -exec php -l {} \; >/dev/null
node --check "$fixture/.wp-plugin-base-admin-ui/src/app.js"
# Rendered literals preserve punctuation, backslashes and marker-like user text.
FIXTURE="$fixture" php <<'PHP'
<?php
$path = getenv('FIXTURE') . '/includes/admin-ui/bootstrap.php';
$expected = 'Owner\'s \\Path "Plugin" ${literal} __PLUGIN_SLUG__';
$found = false;
foreach (token_get_all(file_get_contents($path)) as $token) {
    if (is_array($token) && T_CONSTANT_ENCAPSED_STRING === $token[0] && eval('return ' . $token[1] . ';') === $expected) {
        $found = true;
    }
}
if (!$found) throw new RuntimeException('Plugin name did not round-trip through PHP serialization.');
PHP
printf '\n// Keep consumer code.\n' >> "$fixture/includes/admin-ui/bootstrap.php"
sync_fixture
test "$(grep -c '^RUNTIME_CLASS_PREFIX=' "$fixture/.wp-plugin-base.env")" -eq 1
grep -Fq '// Keep consumer code.' "$fixture/includes/admin-ui/bootstrap.php"
# Auto dependency coverage includes root manifests and preserves project seeds.
printf '{}\n' > "$fixture/composer.json"
printf '{}\n' > "$fixture/package.json"
sync_fixture
grep -Fq 'package-ecosystem: composer' "$fixture/.github/dependabot.yml"
test "$(grep -c 'package-ecosystem: npm' "$fixture/.github/dependabot.yml")" -eq 2
# Combining ecosystem discovery with foundation pin ownership must not leak
# action ignore rules into package update entries.
ruby -rpsych -rjson - "$fixture/.github/dependabot.yml" "$ROOT_DIR/scripts/lib/action-pins.json" <<'RUBY'
document = Psych.safe_load(File.read(ARGV[0]), aliases: false)
updates = document.fetch('updates')
actions = updates.select { |update| update.fetch('package-ecosystem') == 'github-actions' }
abort 'Expected exactly one Actions update policy' unless actions.length == 1
expected = JSON.parse(File.read(ARGV[1])).fetch('actions').keys.map { |name| name.split('/').first(2).join('/') }.uniq.sort
actual = actions.first.fetch('ignore').map { |entry| entry.fetch('dependency-name') }.sort
abort 'Foundation action ownership was lost' unless actual == expected
updates.reject { |update| update.fetch('package-ecosystem') == 'github-actions' }.each do |update|
  abort 'Foundation action ignores leaked into package updates' if update.key?('ignore')
end
abort 'Unrendered dependency marker survived' if File.read(ARGV[0]).include?('__')
RUBY
printf '\nDEPENDABOT_ECOSYSTEMS=github-actions\n' >> "$fixture/.wp-plugin-base.env"
sync_fixture
test "$(grep -c 'package-ecosystem:' "$fixture/.github/dependabot.yml")" -eq 1
# Retired upstream library paths must not survive a managed refresh. Other
# application code in the mixed-ownership parent directory remains untouched.
mkdir -p "$fixture/lib/wp-plugin-base/plugin-update-checker/Puc/v5p6"
printf '<?php // retired vendor file\n' > "$fixture/lib/wp-plugin-base/plugin-update-checker/Puc/v5p6/Retired.php"
printf '<?php // application code\n' > "$fixture/lib/wp-plugin-base/consumer.php"
sync_fixture
test ! -f "$fixture/lib/wp-plugin-base/plugin-update-checker/Puc/v5p6/Retired.php"
test -f "$fixture/lib/wp-plugin-base/consumer.php"
# Host switches cannot regenerate unsupported host workflows after cleanup.
cat >> "$fixture/.wp-plugin-base.env" <<'EOF'
AUTOMATION_PROVIDER=gitlab
WOOCOMMERCE_QIT_ENABLED=false
AUTOMATION_API_BASE=https://gitlab.com/api/v4
EOF
sync_fixture
test -f "$fixture/.gitlab-ci.yml"
test ! -f "$fixture/.github/workflows/woocommerce-status.yml"
test ! -f "$fixture/.github/workflows/simulate-release.yml"
test ! -f "$fixture/.github/dependabot.yml"
test ! -f "$fixture/.github/workflows/woocommerce-qit.yml"
printf '\nWOOCOMMERCE_QIT_ENABLED=true\n' >> "$fixture/.wp-plugin-base.env"
if WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/validate_config.sh" --scope project > "$fixture/qit.log" 2>&1; then
  echo 'GitLab accepted the unsupported GitHub QIT pack.' >&2
  exit 1
fi
grep -Fq 'GitHub-only workflow pack' "$fixture/qit.log"
printf '\nWOOCOMMERCE_QIT_ENABLED=false\n' >> "$fixture/.wp-plugin-base.env"

WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/list_managed_files.sh" --mode stage > "$fixture/stage-paths"
grep -Fxq '.github/workflows/simulate-release.yml' "$fixture/stage-paths"
# Disabling runtime removes managed files but never consumer-owned seeds.
cat >> "$fixture/.wp-plugin-base.env" <<'EOF'
ADMIN_UI_PACK_ENABLED=false
REST_OPERATIONS_PACK_ENABLED=false
ADMIN_UI_EXPERIMENTAL_DATAVIEWS=false
BUILD_SCRIPT=
EOF
sync_fixture
test ! -f "$fixture/lib/wp-plugin-base/admin-ui/bootstrap.php"
test -f "$fixture/includes/admin-ui/bootstrap.php"
# Managed output links must never overwrite a file outside the repository.
external_file="$(mktemp)"
printf 'outside-marker\n' > "$external_file"
rm -f "$fixture/.editorconfig"
ln -s "$external_file" "$fixture/.editorconfig"
if sync_fixture > "$fixture/symlink.log" 2>&1; then
  rm -f "$external_file"
  echo 'Managed output symbolic link was accepted.' >&2
  exit 1
fi
grep -Fxq outside-marker "$external_file"
rm -f "$fixture/.editorconfig" "$external_file"
# Unowned inactive-host paths are preserved without traversal or cleanup.
external_dir="$(mktemp -d)"
printf 'outside-workflow\n' > "$external_dir/ci.yml"
mkdir -p "$fixture/.github"
rm -rf "$fixture/.github/workflows"
ln -s "$external_dir" "$fixture/.github/workflows"
sync_fixture > "$fixture/cleanup-symlink.log" 2>&1
test -L "$fixture/.github/workflows"
test "$(readlink "$fixture/.github/workflows")" = "$external_dir"
grep -Fxq outside-workflow "$external_dir/ci.yml"
rm -f "$fixture/.github/workflows"
rm -rf "$external_dir"
# A recorded managed path still fails before cleanup if replaced by a symlink.
external_file="$(mktemp)"
printf 'outside-owned-workflow\n' > "$external_file"
rm -f "$fixture/.gitlab-ci.yml"
ln -s "$external_file" "$fixture/.gitlab-ci.yml"
printf '\nAUTOMATION_PROFILE=local\n' >> "$fixture/.wp-plugin-base.env"
if sync_fixture > "$fixture/owned-cleanup-symlink.log" 2>&1; then
  rm -f "$external_file"
  echo 'Recorded managed cleanup accepted a symbolic link outside the repository.' >&2
  exit 1
fi
grep -Fq 'must not use symlinks' "$fixture/owned-cleanup-symlink.log"
grep -Fxq outside-owned-workflow "$external_file"
test -L "$fixture/.gitlab-ci.yml"
rm -f "$fixture/.gitlab-ci.yml" "$external_file"
printf '\nAUTOMATION_PROFILE=managed\n' >> "$fixture/.wp-plugin-base.env"
sync_fixture
# AGENTS uses marked-section preservation and must enforce its own link boundary.
external_dir="$(mktemp -d)"
rm -f "$fixture/AGENTS.md"
ln -s "$external_dir/missing.md" "$fixture/AGENTS.md"
if sync_fixture > "$fixture/agents-symlink.log" 2>&1; then
  rm -rf "$external_dir"
  echo 'Managed AGENTS followed a dangling symbolic link.' >&2
  exit 1
fi
test ! -e "$external_dir/missing.md"
rm -f "$fixture/AGENTS.md"
rm -rf "$external_dir"
# Config errors stop before any generation.
for values in github-actions,github-actions auto,npm invalid; do
  printf '\nDEPENDABOT_ECOSYSTEMS=%s\n' "$values" >> "$fixture/.wp-plugin-base.env"
  if WP_PLUGIN_BASE_ROOT="$fixture" bash "$ROOT_DIR/scripts/ci/validate_config.sh" --scope project >/dev/null 2>&1; then
    echo "Invalid dependency coverage accepted: $values" >&2
    exit 1
  fi
done
echo 'Generation ownership, serialization, prefix and dependency contracts passed.'
