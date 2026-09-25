#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/load_config.sh
. "$SCRIPT_DIR/../lib/load_config.sh"
# shellcheck source=../lib/managed_files.sh
. "$SCRIPT_DIR/../lib/managed_files.sh"
# shellcheck source=../lib/quality_pack.sh
. "$SCRIPT_DIR/../lib/quality_pack.sh"
# shellcheck source=../lib/dependabot.sh
. "$SCRIPT_DIR/../lib/dependabot.sh"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

SYNC_MODE=sync
if [ "${1:-}" = --capture-automation-ownership ]; then
  SYNC_MODE=capture-automation-ownership
  shift
fi

wp_plugin_base_require_commands "managed file sync" perl php ruby
config_scope=project
if [ "$SYNC_MODE" = capture-automation-ownership ]; then config_scope=sync; fi
bash "$SCRIPT_DIR/../ci/validate_config.sh" --scope "$config_scope" "${1:-}"

wp_plugin_base_load_config "${1:-}"
wp_plugin_base_require_vars FOUNDATION_RELEASE_SOURCE_PROVIDER FOUNDATION_RELEASE_SOURCE_REFERENCE FOUNDATION_RELEASE_SOURCE_API_BASE FOUNDATION_VERSION PLUGIN_NAME PLUGIN_SLUG MAIN_PLUGIN_FILE README_FILE ZIP_FILE PHP_VERSION NODE_VERSION
CODEOWNERS_REVIEWERS="${CODEOWNERS_REVIEWERS:-}"
WORDPRESS_QUALITY_PACK_ENABLED="${WORDPRESS_QUALITY_PACK_ENABLED:-false}"
WORDPRESS_SECURITY_PACK_ENABLED="${WORDPRESS_SECURITY_PACK_ENABLED:-false}"
GITHUB_RELEASE_UPDATER_ENABLED="${GITHUB_RELEASE_UPDATER_ENABLED:-false}"
GITHUB_RELEASE_UPDATER_REPO_URL="${GITHUB_RELEASE_UPDATER_REPO_URL:-}"
PLUGIN_RUNTIME_UPDATE_PROVIDER="${PLUGIN_RUNTIME_UPDATE_PROVIDER:-none}"
REST_OPERATIONS_PACK_ENABLED="${REST_OPERATIONS_PACK_ENABLED:-false}"
ADMIN_UI_PACK_ENABLED="${ADMIN_UI_PACK_ENABLED:-false}"
RUNTIME_UPDATE_PACK_ENABLED=false
if [ "$PLUGIN_RUNTIME_UPDATE_PROVIDER" != "none" ] || wp_plugin_base_is_true "$GITHUB_RELEASE_UPDATER_ENABLED"; then
  RUNTIME_UPDATE_PACK_ENABLED=true
fi

FOUNDATION_DIR="$ROOT_DIR/.wp-plugin-base"
TEMPLATE_DIR="$FOUNDATION_DIR/templates/child"
AGENTS_MANAGED_START='<!-- wp-plugin-base:agents-start -->'
AGENTS_MANAGED_END='<!-- wp-plugin-base:agents-end -->'

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "Template directory not found: $TEMPLATE_DIR" >&2
  exit 1
fi

# Resolve every producer before changing config, cleaning old files or writing
# templates. Process substitutions hide producer failures from their consumers.
managed_template_pairs="$(wp_plugin_base_print_managed_template_pairs "$TEMPLATE_DIR")" || exit 1
seed_template_pairs="$(wp_plugin_base_print_required_seed_template_pairs "$TEMPLATE_DIR")" || exit 1
active_managed_paths="$(wp_plugin_base_print_managed_paths "$TEMPLATE_DIR")" || exit 1
all_managed_paths="$(wp_plugin_base_print_all_managed_paths "$TEMPLATE_DIR")" || exit 1
all_template_pairs=""
if [ ! -e "$ROOT_DIR/.wp-plugin-base-automation.json" ] && {
  [ -d "$ROOT_DIR/.github" ] || [ -d "$ROOT_DIR/.gitlab" ] || [ -e "$ROOT_DIR/.gitlab-ci.yml" ];
}; then
  all_template_pairs="$(wp_plugin_base_print_all_managed_template_pairs "$TEMPLATE_DIR")" || exit 1
fi


render_template() {
  local source_file="$1"
  local destination_file="$2"
  local runtime_template=false
  local rendered_output
  case "$source_file" in
    "$TEMPLATE_DIR"/rest-operations-pack/*|"$TEMPLATE_DIR"/rest-operations-pack-seed/*|"$TEMPLATE_DIR"/admin-ui-pack/*|"$TEMPLATE_DIR"/admin-ui-pack-seed-*/*)
      runtime_template=true
      ;;
  esac
  export WP_PLUGIN_BASE_RUNTIME_TEMPLATE="$runtime_template" RUNTIME_CLASS_PREFIX
  WP_PLUGIN_BASE_PHPCS_CHILD_RULE=false
  if [ -f "$ROOT_DIR/.wp-plugin-base-quality-pack/phpcs-child.xml" ]; then
    WP_PLUGIN_BASE_PHPCS_CHILD_RULE=true
  fi
  export WP_PLUGIN_BASE_PHPCS_CHILD_RULE

  if [[ "$destination_file" == "$ROOT_DIR"/* ]]; then
    wp_plugin_base_assert_path_within_root "$destination_file" "Managed output"
  fi
  if [ -L "$destination_file" ]; then
    echo "Managed output must not be a symbolic link: $destination_file" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$destination_file")"

  export FOUNDATION_REPOSITORY FOUNDATION_RELEASE_SOURCE_PROVIDER FOUNDATION_RELEASE_SOURCE_REFERENCE FOUNDATION_RELEASE_SOURCE_API_BASE FOUNDATION_VERSION PRODUCTION_ENVIRONMENT CODEOWNERS_REVIEWERS DEFAULT_BRANCH
  export PLUGIN_NAME PLUGIN_SLUG MAIN_PLUGIN_FILE README_FILE ZIP_FILE PHP_VERSION NODE_VERSION VERSION_CONSTANT_NAME DISTIGNORE_FILE
  export WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE GITHUB_RELEASE_UPDATER_REPO_URL PLUGIN_RUNTIME_UPDATE_PROVIDER PLUGIN_RUNTIME_UPDATE_SOURCE_URL AUTOMATION_PROVIDER REST_API_NAMESPACE REST_ABILITIES_ENABLED ADMIN_UI_EXPERIMENTAL_DATAVIEWS
  rendered_output="$(mktemp "$(dirname "$destination_file")/.wp-plugin-base-render.XXXXXX")"
  if [ "$source_file" = "$TEMPLATE_DIR/.github/dependabot.yml" ]; then
    if ! wp_plugin_base_render_dependabot "$source_file" > "$rendered_output"; then
      rm -f "$rendered_output"
      return 1
    fi
  elif ! php "$SCRIPT_DIR/../lib/render_template.php" "$source_file" > "$rendered_output"; then
    rm -f "$rendered_output"
    return 1
  fi
  if [ "$source_file" = "$TEMPLATE_DIR/.gitignore" ] && { [ -n "${BUILD_OUTPUTS:-}" ] || [ -n "${BUILD_OUTPUT_MANIFEST:-}" ]; }; then
    printf '\n# Application-declared generated build artifacts.\n' >> "$rendered_output"
    while IFS= read -r generated_path; do
      [ -n "$generated_path" ] || continue
      printf '/%s\n' "$generated_path" >> "$rendered_output"
    done < <(wp_plugin_base_csv_to_lines "${BUILD_OUTPUTS:-}")
    if [ -n "${BUILD_OUTPUT_MANIFEST:-}" ]; then
      printf '/%s/\n' "$(dirname "$BUILD_OUTPUT_MANIFEST")" >> "$rendered_output"
    fi
  fi
  chmod 644 "$rendered_output"
  mv "$rendered_output" "$destination_file"
}

seed_template_once() {
  local source_file="$1"
  local destination_file="$2"

  if [ -e "$destination_file" ]; then
    return 0
  fi

  render_template "$source_file" "$destination_file"
}

sync_agents_file() {
  local source_file="$1"
  local destination_file="$2"
  local rendered_file
  local stripped_rendered_file
  local updated_file
  local start_count
  local end_count

  wp_plugin_base_assert_path_within_root "$destination_file" "Managed AGENTS output"
  if [ -L "$destination_file" ]; then
    echo "Managed AGENTS output must not be a symbolic link: $destination_file" >&2
    exit 1
  fi

  rendered_file="$(mktemp)"
  stripped_rendered_file="$(mktemp)"
  updated_file="$(mktemp)"

  render_template "$source_file" "$rendered_file"
  awk \
    -v start="$AGENTS_MANAGED_START" \
    -v end="$AGENTS_MANAGED_END" \
    '$0 != start && $0 != end { print }' \
    "$rendered_file" > "$stripped_rendered_file"

  if [ ! -e "$destination_file" ]; then
    mkdir -p "$(dirname "$destination_file")"
    cp "$rendered_file" "$destination_file"
    rm -f "$rendered_file" "$stripped_rendered_file" "$updated_file"
    return 0
  fi

  if [ ! -f "$destination_file" ]; then
    echo "AGENTS.md must be a regular file so sync can preserve project-owned instructions: $destination_file" >&2
    rm -f "$rendered_file" "$stripped_rendered_file" "$updated_file"
    exit 1
  fi

  start_count="$(grep -Fxc "$AGENTS_MANAGED_START" "$destination_file" || true)"
  end_count="$(grep -Fxc "$AGENTS_MANAGED_END" "$destination_file" || true)"

  if [ "$start_count" -eq 1 ] && [ "$end_count" -eq 1 ]; then
    if ! WP_PLUGIN_BASE_AGENTS_RENDERED="$rendered_file" \
      WP_PLUGIN_BASE_AGENTS_START="$AGENTS_MANAGED_START" \
      WP_PLUGIN_BASE_AGENTS_END="$AGENTS_MANAGED_END" \
      perl -0pe '
        BEGIN {
          local $/;
          open my $fh, "<", $ENV{WP_PLUGIN_BASE_AGENTS_RENDERED} or die "open rendered AGENTS.md: $!";
          $replacement = <$fh>;
          # The match excludes the existing end-marker line ending.
          $replacement =~ s/\r?\n\z//;
          $start = $ENV{WP_PLUGIN_BASE_AGENTS_START};
          $end = $ENV{WP_PLUGIN_BASE_AGENTS_END};
        }
        s/\Q$start\E.*?\Q$end\E/$replacement/s or die "managed AGENTS.md section not found\n";
      ' "$destination_file" > "$updated_file"; then
      echo "AGENTS.md has invalid managed-section markers; expected one start marker before one end marker." >&2
      rm -f "$rendered_file" "$stripped_rendered_file" "$updated_file"
      exit 1
    fi
    mv "$updated_file" "$destination_file"
    rm -f "$rendered_file" "$stripped_rendered_file"
    return 0
  fi

  if [ "$start_count" -ne 0 ] || [ "$end_count" -ne 0 ]; then
    echo "AGENTS.md has invalid managed-section markers; expected exactly one start marker and one end marker." >&2
    rm -f "$rendered_file" "$stripped_rendered_file" "$updated_file"
    exit 1
  fi

  WP_PLUGIN_BASE_AGENTS_RENDERED="$rendered_file" \
    WP_PLUGIN_BASE_AGENTS_LEGACY="$stripped_rendered_file" \
    perl -0pe '
      BEGIN {
        local $/;
        open my $rfh, "<", $ENV{WP_PLUGIN_BASE_AGENTS_RENDERED} or die "open rendered AGENTS.md: $!";
        open my $lfh, "<", $ENV{WP_PLUGIN_BASE_AGENTS_LEGACY} or die "open legacy AGENTS.md: $!";
        $replacement = <$rfh>;
        $legacy = <$lfh>;
      }
      if (index($_, $legacy) >= 0) {
        s/\Q$legacy\E/$replacement/s;
      } elsif (length($_) == 0) {
        $_ = $replacement;
      } else {
        s/\s*\z/\n\n/s;
        $_ .= $replacement;
      }
    ' "$destination_file" > "$updated_file"
  mv "$updated_file" "$destination_file"
  rm -f "$rendered_file" "$stripped_rendered_file"
}

warn_quality_pack_bootstrap_migration_risk() {
  local managed_bootstrap_template="$TEMPLATE_DIR/quality-pack/tests/bootstrap.php"
  local managed_bootstrap_path="$ROOT_DIR/tests/bootstrap.php"
  local child_bootstrap_path="$ROOT_DIR/tests/wp-plugin-base/bootstrap-child.php"
  local rendered_template

  if ! wp_plugin_base_quality_pack_phpunit_bridge_enabled && ! wp_plugin_base_quality_pack_is_full_enabled; then
    return 0
  fi

  if [ ! -f "$managed_bootstrap_template" ] || [ ! -f "$managed_bootstrap_path" ]; then
    return 0
  fi

  rendered_template="$(mktemp)"
  render_template "$managed_bootstrap_template" "$rendered_template"

  if ! cmp -s "$managed_bootstrap_path" "$rendered_template" && [ ! -s "$child_bootstrap_path" ]; then
    {
      echo "Warning: tests/bootstrap.php is managed by wp-plugin-base and was customized in this repository."
      echo "Warning: Child-specific PHPUnit preloads and support-class requires should live in tests/wp-plugin-base/bootstrap-child.php."
      echo "Warning: Sync may overwrite tests/bootstrap.php and break post-sync CI until those preloads are moved."
      echo "Warning: See docs/existing-project-migration.md#phpunit-bootstrap-migration and docs/troubleshooting.md#post-sync-phpunit-bootstrap-regressions."
    } >&2
  fi

  rm -f "$rendered_template"
}

remove_stale_managed_aliases() {
  if [ "$DISTIGNORE_FILE" != ".distignore" ]; then
    rm -f "$ROOT_DIR/.distignore"
  fi

  if [ "$WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE" != ".wp-plugin-base-security-suppressions.json" ]; then
    rm -f "$ROOT_DIR/.wp-plugin-base-security-suppressions.json"
  fi
}

# Enumerate both enabled output and removable managed output from the same manifest.
# Seed files are consumer-owned after first generation and never enter this cleanup.
remove_disabled_managed_files() {
  local destination_path
  while IFS= read -r destination_path; do
    [ -n "$destination_path" ] || continue
    case "$destination_path" in
      .github/*|.gitlab/*|.gitlab-ci.yml)
        # Host file removal requires byte-level ownership, never just a filename.
        if grep -Fxq "$destination_path" <<< "$automation_removals"; then
          rm -f "$ROOT_DIR/$destination_path"
        fi
        continue
        ;;
    esac
    if ! grep -Fxq "$destination_path" <<< "$active_managed_paths"; then
      wp_plugin_base_assert_path_within_root "$ROOT_DIR/$destination_path" "Managed cleanup"
      rm -f "$ROOT_DIR/$destination_path"
    fi
  done <<< "$all_managed_paths"
}

# Render hosted automation before any project mutation, then check recorded
# ownership and conflicts. Other application workflows remain untouched.
automation_scratch="$(mktemp -d)"
trap 'rm -rf "$automation_scratch"' EXIT
: > "$automation_scratch/desired"
: > "$automation_scratch/legacy"
for inventory in desired legacy; do
  template_pairs="$managed_template_pairs"
  if [ "$inventory" = legacy ]; then template_pairs="$all_template_pairs"; fi
  while IFS=$'\t' read -r source_file destination_path; do
    case "$destination_path" in
      .github/*|.gitlab/*|.gitlab-ci.yml)
        if [ "$inventory" = legacy ] && [ ! -e "$ROOT_DIR/$destination_path" ]; then continue; fi
        render_template "$source_file" "$automation_scratch/rendered"
        digest="$(ruby -rdigest -e 'puts Digest::SHA256.file(ARGV[0]).hexdigest' "$automation_scratch/rendered")"
        printf '%s\t%s\n' "$digest" "$destination_path" >> "$automation_scratch/$inventory"
        ;;
    esac
  done <<< "$template_pairs"
done
export AUTOMATION_PROFILE
unset WP_PLUGIN_BASE_PRIOR_AUTOMATION_RECEIPT
# A first update from a pre-receipt release has already replaced the vendor.
# Reconstruct the previous committed template/config generation with our trusted
# renderer, never by executing old scripts or claiming files by filename.
if [ "$SYNC_MODE" = sync ] && [ ! -e "$ROOT_DIR/.wp-plugin-base-automation.json" ] &&
  { [ -d "$ROOT_DIR/.github" ] || [ -d "$ROOT_DIR/.gitlab" ] || [ -e "$ROOT_DIR/.gitlab-ci.yml" ]; } &&
  git -C "$ROOT_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
  if python3 "$SCRIPT_DIR/recover_automation_ownership.py" "$ROOT_DIR" "$CONFIG_PATH" "$automation_scratch/previous-receipt.json" 2>"$automation_scratch/recovery-error"; then
    export WP_PLUGIN_BASE_PRIOR_AUTOMATION_RECEIPT="$automation_scratch/previous-receipt.json"
  else
    cat "$automation_scratch/recovery-error" >&2
  fi
fi
automation_removals="$(ruby "$SCRIPT_DIR/../lib/automation_ownership.rb" "$ROOT_DIR" "$automation_scratch/desired" "$automation_scratch/legacy" check)" || exit 1
if [ "$SYNC_MODE" = capture-automation-ownership ]; then
  wp_plugin_base_require_managed_automation "Legacy automation ownership capture"
  ruby "$SCRIPT_DIR/../lib/automation_ownership.rb" "$ROOT_DIR" "$automation_scratch/desired" "$automation_scratch/legacy" write
  echo "Captured byte-verified automation ownership without synchronizing project files."
  exit 0
fi

# A prefix is persisted once: later loads must not infer a different identity
# after seed files appear. Existing runtime consumers keep their historic names.
if { wp_plugin_base_is_true "$REST_OPERATIONS_PACK_ENABLED" || wp_plugin_base_is_true "$ADMIN_UI_PACK_ENABLED"; } &&
  ! grep -Eq '^[[:space:]]*RUNTIME_CLASS_PREFIX=' "$CONFIG_PATH" &&
  [ -z "${RUNTIME_CLASS_PREFIX:-}" ] &&
  [ ! -e "$ROOT_DIR/lib/wp-plugin-base/rest-operations" ] &&
  [ ! -e "$ROOT_DIR/lib/wp-plugin-base/admin-ui" ] &&
  [ ! -e "$ROOT_DIR/includes/rest-operations" ] &&
  [ ! -e "$ROOT_DIR/includes/admin-ui" ]; then
  RUNTIME_CLASS_PREFIX="$(PLUGIN_SLUG="$PLUGIN_SLUG" php -r '$slug = getenv("PLUGIN_SLUG"); echo "Wpb_" . substr(str_replace("-", "_", $slug), 0, 40) . "_" . substr(hash("sha256", $slug), 0, 12) . "_";')"
  printf '\nRUNTIME_CLASS_PREFIX=%s\n' "$RUNTIME_CLASS_PREFIX" >> "$CONFIG_PATH"
  export RUNTIME_CLASS_PREFIX
fi

warn_quality_pack_bootstrap_migration_risk
remove_stale_managed_aliases
remove_disabled_managed_files
# Vendored upstream libraries are wholly managed. Remove retired version files
# before copying the verified new tree; current-template enumeration alone cannot
# identify paths that vanished in an upstream release.
vendor_path="$ROOT_DIR/lib/wp-plugin-base/plugin-update-checker"
wp_plugin_base_assert_path_within_root "$vendor_path" "Vendored updater directory"
if [ -L "$vendor_path" ]; then
  echo "Vendored updater directory must not be a symbolic link." >&2
  exit 1
fi
rm -rf "$vendor_path"

while IFS=$'\t' read -r source_file destination_path; do
  [ -n "$source_file" ] || continue
  case "$source_file" in
    "$TEMPLATE_DIR"/github-release-updater-pack/lib/wp-plugin-base/plugin-update-checker/*)
      mkdir -p "$(dirname "$ROOT_DIR/$destination_path")"
      cp "$source_file" "$ROOT_DIR/$destination_path"
      ;;
    *) render_template "$source_file" "$ROOT_DIR/$destination_path" ;;
  esac
done <<< "$managed_template_pairs"

while IFS=$'\t' read -r source_file destination_path; do
  [ -n "$source_file" ] || continue
  if [ "$destination_path" = AGENTS.md ]; then
    sync_agents_file "$source_file" "$ROOT_DIR/$destination_path"
  else
    seed_template_once "$source_file" "$ROOT_DIR/$destination_path"
  fi
done <<< "$seed_template_pairs"

seed_template_once "$TEMPLATE_DIR/CHANGELOG.md" "$ROOT_DIR/CHANGELOG.md"
# Remove retired foundation-owned test names, but preserve current consumer seeds.
rm -f "$ROOT_DIR/tests/test-plugin-loads.php" "$ROOT_DIR/tests/PluginLoadsTest.php"

if [ "${AUTOMATION_PROFILE:-managed}" = managed ] && [ "${AUTOMATION_PROVIDER:-github}" = "github" ]; then
  ruby "$SCRIPT_DIR/migrate_action_pins.rb" "$ROOT_DIR" "${WP_PLUGIN_BASE_ACTION_MIGRATION_MANIFEST:-}"
fi

ruby "$SCRIPT_DIR/../lib/automation_ownership.rb" "$ROOT_DIR" "$automation_scratch/desired" "$automation_scratch/legacy" write
echo "Synchronized managed project files (${AUTOMATION_PROFILE} automation profile)."
