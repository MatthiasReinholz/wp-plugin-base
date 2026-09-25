#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
cp -R "$ROOT_DIR/tests/fixtures/quality-ready/." "$fixture_dir/"
mkdir -p "$fixture_dir/.wp-plugin-base" "$fixture_dir/.github/workflows" "$fixture_dir/.wp-plugin-base-quality-pack"
rsync -a --exclude '.git' "$ROOT_DIR/" "$fixture_dir/.wp-plugin-base/"
cat > "$fixture_dir/.wp-plugin-base-quality-pack/phpcs-child.xml" <<'XML'
<?xml version="1.0"?>
<ruleset name="Child"><exclude-pattern>*/legacy/example.php</exclude-pattern></ruleset>
XML
cp "$fixture_dir/.wp-plugin-base-quality-pack/phpcs-child.xml" "$fixture_dir/expected-overlay.xml"
cat > "$fixture_dir/.github/workflows/custom.yml" <<'YAML'
name: Custom
permissions: {contents: read}
on: push
jobs:
  custom:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # retain
YAML
printf '%s\n' '{"private":true}' > "$fixture_dir/package.json"
WP_PLUGIN_BASE_ROOT="$fixture_dir" WP_PLUGIN_BASE_ACTION_MIGRATION_MANIFEST="$fixture_dir/migrations.txt" \
  bash "$ROOT_DIR/scripts/update/sync_child_repo.sh" >/dev/null
cmp "$fixture_dir/expected-overlay.xml" "$fixture_dir/.wp-plugin-base-quality-pack/phpcs-child.xml"
grep -Fq '<rule ref=".wp-plugin-base-quality-pack/phpcs-child.xml"/>' "$fixture_dir/.phpcs.xml.dist"
grep -Fqx '.github/workflows/custom.yml' "$fixture_dir/migrations.txt"
ruby "$ROOT_DIR/scripts/update/list_migrated_action_paths.rb" "$fixture_dir" "$fixture_dir/migrations.txt" | grep -Fqx '.github/workflows/custom.yml'
git -C "$fixture_dir" init -q
# Execute the generated workflow body, rather than recreating its staging logic.
ruby -rpsych -e '
  workflow = Psych.safe_load(File.read(ARGV[0]), aliases: false)
  step = workflow.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }.find { |item| item["name"] == "Resolve managed staging paths" }
  abort "Missing staging workflow step" unless step
  File.write(ARGV[1], step.fetch("run"))
' "$fixture_dir/.github/workflows/update-foundation.yml" "$fixture_dir/staging.sh"
cp "$fixture_dir/migrations.txt" "$fixture_dir/foundation-action-migrations.txt"
(
  cd "$fixture_dir"
  RUNNER_TEMP="$fixture_dir" GITHUB_OUTPUT="$fixture_dir/staging-output" bash "$fixture_dir/staging.sh"
  staging_paths="$(sed -n 's/^value=//p' "$fixture_dir/staging-output")"
  IFS=',' read -r -a paths <<< "$staging_paths"
  for path in "${paths[@]}"; do
    if [ -e "$path" ]; then git add -- "$path"; fi
  done
)
git -C "$fixture_dir" diff --cached --name-only > "$fixture_dir/staged-paths"
grep -Fqx '.github/workflows/custom.yml' "$fixture_dir/staged-paths"
rm "$fixture_dir/.wp-plugin-base-quality-pack/phpcs-child.xml"
WP_PLUGIN_BASE_ROOT="$fixture_dir" bash "$ROOT_DIR/scripts/update/sync_child_repo.sh" >/dev/null
if grep -Fq 'phpcs-child.xml' "$fixture_dir/.phpcs.xml.dist"; then
  echo 'Deleted PHPCS overlay was still included after sync.' >&2
  exit 1
fi
echo 'Child action migration, staging, and PHPCS overlay sync tests passed.'
