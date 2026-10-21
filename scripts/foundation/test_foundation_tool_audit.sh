#!/usr/bin/env bash
# Foundation-owned tool lock advisories warn in projects and block foundation validation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$ROOT_DIR/scripts/lib/require_tools.sh"
# shellcheck source=../lib/wordpress_tooling.sh
. "$ROOT_DIR/scripts/lib/wordpress_tooling.sh"

# Retries are irrelevant to the policy under test.
sleep() { :; }
passing_audit() { return 0; }
failing_audit() { return 1; }

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

WP_PLUGIN_BASE_FOUNDATION_TOOL_AUDIT=strict wp_plugin_base_audit_foundation_tool_lock "Fixture audit" passing_audit
wp_plugin_base_audit_foundation_tool_lock "Fixture audit" passing_audit

if ! (unset WP_PLUGIN_BASE_FOUNDATION_TOOL_AUDIT; GITHUB_ACTIONS=true wp_plugin_base_audit_foundation_tool_lock "Fixture audit" failing_audit) >"$log" 2>&1; then
  echo "Foundation tool lock advisories must not block project validation." >&2
  exit 1
fi
grep -Fq 'Warning: Fixture audit did not pass for wp-plugin-base development tooling' "$log"
grep -Fq '::warning title=wp-plugin-base tooling audit::' "$log"

if (WP_PLUGIN_BASE_FOUNDATION_TOOL_AUDIT=strict wp_plugin_base_audit_foundation_tool_lock "Fixture audit" failing_audit) >/dev/null 2>&1; then
  echo "Foundation validation must block on foundation tool lock advisories." >&2
  exit 1
fi

echo "Foundation tool lock audit policy tests passed."
