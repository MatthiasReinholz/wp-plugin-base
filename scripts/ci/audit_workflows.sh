#!/usr/bin/env bash

set -euo pipefail

TARGET_ROOT="${1:-}"

if [ -z "$TARGET_ROOT" ]; then
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    TARGET_ROOT="$(git rev-parse --show-toplevel)"
  else
    TARGET_ROOT="$(pwd)"
  fi
fi

if [ ! -d "$TARGET_ROOT" ]; then
  echo "Target root does not exist: $TARGET_ROOT" >&2
  exit 1
fi

declare -a workflow_dirs=()
declare -a scan_dirs=()
declare -a workflow_files=()

for dir in \
  "$TARGET_ROOT/.github/workflows" \
  "$TARGET_ROOT/templates/child/.github/workflows" \
  "$TARGET_ROOT/.wp-plugin-base/.github/workflows"
do
  if [ -d "$dir" ]; then
    workflow_dirs+=("$dir")
  fi
done

for dir in \
  "$TARGET_ROOT/.github/workflows" \
  "$TARGET_ROOT/templates/child/.github/workflows" \
  "$TARGET_ROOT/scripts" \
  "$TARGET_ROOT/.wp-plugin-base/.github/workflows" \
  "$TARGET_ROOT/.wp-plugin-base/scripts"
do
  if [ -d "$dir" ]; then
    scan_dirs+=("$dir")
  fi
done

if [ "${#workflow_dirs[@]}" -eq 0 ]; then
  echo "No workflow directories found under $TARGET_ROOT" >&2
  exit 1
fi

while IFS= read -r file; do
  workflow_files+=("$file")
done < <(find "${workflow_dirs[@]}" -type f -name '*.yml' | sort)

if [ "${#workflow_files[@]}" -eq 0 ]; then
  echo "No workflow files found under $TARGET_ROOT" >&2
  exit 1
fi

export WP_PLUGIN_BASE_AUDIT_ROOT="$TARGET_ROOT"
export WP_PLUGIN_BASE_AUDIT_WORKFLOWS
WP_PLUGIN_BASE_AUDIT_WORKFLOWS="$(printf '%s\n' "${workflow_files[@]}")"

ruby <<'RUBY'
require "yaml"

root = ENV.fetch("WP_PLUGIN_BASE_AUDIT_ROOT")
workflow_files = ENV.fetch("WP_PLUGIN_BASE_AUDIT_WORKFLOWS").split("\n").reject(&:empty?)

expected_permissions = {
  "foundation-ci.yml" => { "contents" => "read" },
  "ci.yml" => { "contents" => "read" },
  "prepare-foundation-release.yml" => { "contents" => "write", "pull-requests" => "write" },
  "prepare-release.yml" => { "contents" => "write", "pull-requests" => "write" },
  "update-foundation.yml" => { "contents" => "write", "pull-requests" => "write" },
  "finalize-foundation-release.yml" => { "contents" => "write", "attestations" => "write", "id-token" => "write" },
  "release-foundation.yml" => { "contents" => "write", "pull-requests" => "read", "attestations" => "write", "id-token" => "write" },
  "finalize-release.yml" => { "contents" => "write", "attestations" => "write", "id-token" => "write" },
  "release.yml" => { "contents" => "write", "pull-requests" => "read", "attestations" => "write", "id-token" => "write" }
}

errors = []

workflow_files.each do |file|
  data = YAML.load_file(file) || {}
  permissions = data["permissions"]
  trigger_block = data["on"] || data[true]
  basename = File.basename(file)
  expected = expected_permissions[basename]

  if permissions.nil?
    errors << "#{file}: missing top-level permissions block"
    next
  end

  unless permissions.is_a?(Hash)
    errors << "#{file}: permissions must be an explicit mapping, found #{permissions.inspect}"
    next
  end

  if permissions.values.any? { |value| value == "write-all" }
    errors << "#{file}: write-all permissions are not allowed"
  end

  if expected.nil?
    errors << "#{file}: no audit policy defined for workflow #{basename}"
    next
  end

  normalized = permissions.transform_keys(&:to_s)
  if normalized != expected
    errors << "#{file}: permissions #{normalized.inspect} do not match expected #{expected.inspect}"
  end

  if trigger_block.is_a?(Hash) && trigger_block.key?("pull_request_target")
    file_contents = File.read(file)
    required_fragments = [
      "github.event.pull_request.merged == true",
      "github.event.pull_request.head.repo.full_name == github.repository",
      "startsWith(github.event.pull_request.head.ref, 'release/') || startsWith(github.event.pull_request.head.ref, 'hotfix/')"
    ]

    unless required_fragments.all? { |fragment| file_contents.include?(fragment) }
      errors << "#{file}: pull_request_target workflows must be limited to merged internal release/hotfix branches"
    end
  end
end

unless errors.empty?
  errors.each { |error| warn(error) }
  exit 1
end
RUBY

declare -a allowed_actions=(
  "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd"
  "actions/setup-node@53b83947a5a98c8d113130e565377fae1a50d02f"
  "actions/upload-artifact@bbbca2ddaa5d8feaa63e36b76fdaad77386f024f"
  "actions/attest-build-provenance@a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32"
  "shivammathur/setup-php@accd6127cb78bee3e8082180cb391013d204ef9f"
)

declare -a uses_entries=()
while IFS= read -r entry; do
  uses_entries+=("$entry")
done < <(
  perl -ne '
    if (/^[[:space:]]*uses:[[:space:]]*([^[:space:]]+)/) {
      print "$ARGV:$.:$1\n";
    }
  ' "${workflow_files[@]}"
)

for entry in "${uses_entries[@]}"; do
  file="${entry%%:*}"
  rest="${entry#*:}"
  line="${rest%%:*}"
  ref="${entry##*:}"

  if [[ "$ref" == ./* ]]; then
    continue
  fi

  if [[ ! "$ref" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+@[0-9a-f]{40}$ ]]; then
    echo "${file}:${line}: action reference must be pinned to a full-length commit SHA: ${ref}" >&2
    exit 1
  fi

  allowed=false
  for action in "${allowed_actions[@]}"; do
    if [ "$ref" = "$action" ]; then
      allowed=true
      break
    fi
  done

  if [ "$allowed" != true ]; then
    echo "${file}:${line}: action is not in the approved allowlist: ${ref}" >&2
    exit 1
  fi
done

declare -a scan_files=()
while IFS= read -r file; do
  case "$file" in
    */scripts/ci/audit_workflows.sh|*/.github/workflows/foundation-ci.yml)
      continue
      ;;
  esac
  scan_files+=("$file")
done < <(find "${scan_dirs[@]}" -type f \( -name '*.yml' -o -name '*.sh' \) | sort)

if rg -n -e 'curl[^[:cntrl:]]*\|[[:space:]]*(bash|sh)\b' -e 'wget[^[:cntrl:]]*\|[[:space:]]*(bash|sh)\b' "${scan_files[@]}" >/dev/null 2>&1; then
  echo "Remote script execution patterns such as curl|bash or wget|sh are not allowed." >&2
  rg -n -e 'curl[^[:cntrl:]]*\|[[:space:]]*(bash|sh)\b' -e 'wget[^[:cntrl:]]*\|[[:space:]]*(bash|sh)\b' "${scan_files[@]}" >&2
  exit 1
fi

while IFS=: read -r file line url; do
  [ -n "$url" ] || continue
  host="${url#https://}"
  host="${host#http://}"
  host="${host%%/*}"
  host="${host%%\$\{*}"
  case "$host" in
    api.github.com|github.com|uploads.github.com|plugins.svn.wordpress.org)
      ;;
    *)
      echo "${file}:${line}: URL host is not allowlisted: ${url}" >&2
      exit 1
      ;;
  esac
done < <(perl -ne 'while (m{(https?://[^\s"'\''()]+)}g) { print "$ARGV:$.:$1\n"; }' "${scan_files[@]}")

while IFS=: read -r file line content; do
  [ -n "$content" ] || continue
  trimmed="$(printf '%s' "$content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ "$trimmed" != "run: sudo apt-get update && sudo apt-get install -y subversion" ]; then
    echo "${file}:${line}: apt-get usage is not allowlisted: ${trimmed}" >&2
    exit 1
  fi
done < <(grep -n "apt-get" "${scan_files[@]}" || true)

echo "Workflow audit passed for $TARGET_ROOT"
