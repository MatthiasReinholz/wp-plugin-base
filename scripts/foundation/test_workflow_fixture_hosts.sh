#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/.github/workflows"
cat > "$fixture/.github/workflows/ci.yml" <<'EOF'
name: fixture
on: workflow_dispatch
permissions:
  contents: read
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - run: echo fixture
EOF

# Construct this reserved fixture URL as data; it is never contacted.
fixture_scheme=https
fixture_host=gitlab.example.test
fixture_url="${fixture_scheme}://${fixture_host}/group/repo.git"
for prefix in scripts .wp-plugin-base/scripts; do
  allowed="$fixture/$prefix/foundation/test_create_or_update_pr_auth_header_reset.sh"
  mkdir -p "$(dirname "$allowed")"
  printf 'echo "%s"\n' "$fixture_url" > "$allowed"
  bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$fixture" > "$fixture/audit.log" 2>&1 || {
    cat "$fixture/audit.log" >&2
    exit 1
  }
  production="$fixture/$prefix/release/publish.sh"
  mkdir -p "$(dirname "$production")"
  mv "$allowed" "$production"
  if bash "$ROOT_DIR/scripts/ci/audit_workflows.sh" "$fixture" > "$fixture/audit.log" 2>&1; then
    echo "Reserved test host was incorrectly accepted in production code." >&2
    exit 1
  fi
  grep -Fq 'URL host is not allowlisted' "$fixture/audit.log"
  rm "$production"
done

echo "Reserved workflow fixture hosts remain limited to their exact test paths."
