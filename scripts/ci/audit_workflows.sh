#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/require_tools.sh
. "$SCRIPT_DIR/../lib/require_tools.sh"

wp_plugin_base_require_commands "workflow audit" git ruby perl

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
declare -a action_dirs=()
declare -a scan_dirs=()
declare -a workflow_files=()
declare -a action_files=()

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
  "$TARGET_ROOT/.github/actions" \
  "$TARGET_ROOT/templates/child/.github/actions" \
  "$TARGET_ROOT/.wp-plugin-base/.github/actions"
do
  if [ -d "$dir" ]; then
    action_dirs+=("$dir")
  fi
done

for dir in \
  "$TARGET_ROOT/.github/workflows" \
  "$TARGET_ROOT/templates/child/.github/workflows" \
  "$TARGET_ROOT/scripts" \
  "$TARGET_ROOT/.github/actions" \
  "$TARGET_ROOT/templates/child/.github/actions" \
  "$TARGET_ROOT/.wp-plugin-base/.github/workflows" \
  "$TARGET_ROOT/.wp-plugin-base/.github/actions" \
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
done < <(find "${workflow_dirs[@]}" -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)

if [ "${#workflow_files[@]}" -eq 0 ]; then
  echo "No workflow files found under $TARGET_ROOT" >&2
  exit 1
fi

while IFS= read -r file; do
  [ -n "$file" ] || continue
  echo "Workflow files must use the .yml extension: $file" >&2
  exit 1
done < <(printf '%s\n' "${workflow_files[@]}" | grep -E '\.yaml$' || true)

if [ "${#action_dirs[@]}" -gt 0 ]; then
  while IFS= read -r file; do
    action_files+=("$file")
  done < <(find "${action_dirs[@]}" -type f \( -name 'action.yml' -o -name 'action.yaml' \) | sort)
fi

export WP_PLUGIN_BASE_AUDIT_ROOT="$TARGET_ROOT"
export WP_PLUGIN_BASE_AUDIT_WORKFLOWS
WP_PLUGIN_BASE_AUDIT_WORKFLOWS="$(printf '%s\n' "${workflow_files[@]}")"
export WP_PLUGIN_BASE_AUDIT_ACTIONS
if [ "${#action_files[@]}" -gt 0 ]; then
  WP_PLUGIN_BASE_AUDIT_ACTIONS="$(printf '%s\n' "${action_files[@]}")"
else
  WP_PLUGIN_BASE_AUDIT_ACTIONS=''
fi

ruby <<'RUBY'
require "psych"

root = ENV.fetch("WP_PLUGIN_BASE_AUDIT_ROOT")
workflow_files = ENV.fetch("WP_PLUGIN_BASE_AUDIT_WORKFLOWS").split("\n").reject(&:empty?)
action_files = ENV.fetch("WP_PLUGIN_BASE_AUDIT_ACTIONS", "").split("\n").reject(&:empty?)

expected_permissions = {
  "foundation-ci.yml" => { "contents" => "read" },
  "scorecard.yml" => { "contents" => "read" },
  "ci.yml" => { "contents" => "read" },
  "woocommerce-qit.yml" => { "contents" => "read" },
  "prepare-foundation-release.yml" => { "contents" => "read", "pull-requests" => "read" },
  "prepare-release.yml" => { "contents" => "read", "pull-requests" => "read" },
  "update-foundation.yml" => { "contents" => "read", "pull-requests" => "read" },
  "update-plugin-check.yml" => { "contents" => "read", "pull-requests" => "read" },
  "finalize-foundation-release.yml" => { "contents" => "read" },
  "release-foundation.yml" => { "contents" => "read", "pull-requests" => "read" },
  "finalize-release.yml" => { "contents" => "read" },
  "release.yml" => { "contents" => "read", "pull-requests" => "read" }
}

expected_job_permissions = {
  "scorecard.yml" => {
    "analysis" => {
      "actions" => "read",
      "checks" => "read",
      "contents" => "read",
      "id-token" => "write",
      "issues" => "read",
      "pull-requests" => "read",
      "security-events" => "write"
    }
  },
  "ci.yml" => {
    "wordpress-readiness" => {
      "contents" => "read",
      "security-events" => "write"
    }
  },
  "foundation-ci.yml" => {
    "release-security-smoke" => {
      "contents" => "read",
      "id-token" => "write"
    }
  },
  "prepare-foundation-release.yml" => {
    "prepare" => {
      "contents" => "write",
      "pull-requests" => "write"
    }
  },
  "prepare-release.yml" => {
    "prepare" => {
      "contents" => "write",
      "pull-requests" => "write"
    }
  },
  "update-foundation.yml" => {
    "update" => {
      "contents" => "write",
      "pull-requests" => "write"
    }
  },
  "update-plugin-check.yml" => {
    "update" => {
      "contents" => "write",
      "pull-requests" => "write"
    }
  },
  "finalize-foundation-release.yml" => {
    "release" => {
      "contents" => "write",
      "attestations" => "write",
      "id-token" => "write"
    }
  },
  "release-foundation.yml" => {
    "release" => {
      "contents" => "write",
      "pull-requests" => "read",
      "attestations" => "write",
      "id-token" => "write"
    }
  },
  "finalize-release.yml" => {
    "release" => {
      "contents" => "write",
      "attestations" => "write",
      "id-token" => "write"
    }
  },
  "release.yml" => {
    "release" => {
      "contents" => "write",
      "pull-requests" => "read",
      "attestations" => "write",
      "id-token" => "write"
    }
  }
}

expected_pull_request_target_conditions = {
  "finalize-foundation-release.yml" => {
    "release" => "github.event.pull_request.merged == true && github.event.pull_request.base.ref == 'main' && github.event.pull_request.head.repo.full_name == github.repository && (startsWith(github.event.pull_request.head.ref, 'release/') || startsWith(github.event.pull_request.head.ref, 'hotfix/'))"
  },
  "finalize-release.yml" => {
    "release" => "github.event.pull_request.merged == true && github.event.pull_request.base.ref == 'main' && github.event.pull_request.head.repo.full_name == github.repository && (startsWith(github.event.pull_request.head.ref, 'release/') || startsWith(github.event.pull_request.head.ref, 'hotfix/'))"
  }
}

custom_permission_policy = {
  "actions" => "read",
  "checks" => "read",
  "contents" => "read",
  "issues" => "read",
  "pull-requests" => "read",
  "security-events" => "write"
}

permission_rank = {
  "none" => 0,
  "read" => 1,
  "write" => 2
}

errors = []

validate_permissions_mapping = lambda do |label, permissions|
  unless permissions.is_a?(Hash)
    errors << "#{label}: permissions must be an explicit mapping, found #{permissions.inspect}"
    next
  end

  normalized = {}
  permissions.each do |key, value|
    key = key.to_s
    value = value.to_s

    unless ["read", "write", "none"].include?(value)
      errors << "#{label}: unsupported permission value #{value.inspect} for #{key.inspect}"
      next
    end

    normalized[key] = value
  end

  normalized
end

validate_permissions_against_policy = lambda do |label, permissions, policy|
  return unless permissions

  permissions.each do |scope, value|
    max_value = policy[scope]
    if max_value.nil?
      errors << "#{label}: permission scope #{scope.inspect} is not allowed by policy"
      next
    end

    if permission_rank.fetch(value) > permission_rank.fetch(max_value)
      errors << "#{label}: permission #{scope.inspect}=#{value.inspect} exceeds allowed maximum #{max_value.inspect}"
    end
  end
end

validate_job_permissions_subset = lambda do |label, workflow_permissions, job_permissions|
  return unless job_permissions

  job_permissions.each do |scope, value|
    workflow_value = workflow_permissions.fetch(scope, "none")
    if permission_rank.fetch(value) > permission_rank.fetch(workflow_value)
      errors << "#{label}: permission #{scope.inspect}=#{value.inspect} exceeds the workflow-level permission #{workflow_value.inspect}"
    end
  end
end

normalize_condition = lambda do |value|
  value.to_s.gsub(/\s+/, " ").strip
end

script_interpreter_pattern = "(bash|sh|source|\\.|python(?:[0-9]+(?:\\.[0-9]+){0,2})?|node(?:js)?|perl|ruby|php)"
local_helper_pattern = %r{
  \b(?:bash|sh|source|\.|python(?:[0-9]+(?:\.[0-9]+){0,2})?|node(?:js)?|perl|ruby|php)\b
  [^\n]*
  (?:
    (?:\.\.?/)?[A-Za-z0-9_./-]+\.(?:sh|bash|py|js|mjs|cjs|pl|rb|php)
  )
}ix

run_body_executes_remote_code = lambda do |label, body|
  normalized = body.to_s.gsub("\r\n", "\n")
  return if normalized.empty?

  if normalized.match?(/\b(curl|wget)[^\n|]*\|[ \t]*#{script_interpreter_pattern}\b/i) ||
    normalized.match?(/#{script_interpreter_pattern}[ \t]*<\([ \t]*(curl|wget)\b/i) ||
    normalized.match?(/\b(curl|wget)[^\n]*(&&|;)[^\n]*\b#{script_interpreter_pattern}\b/i)
    errors << "#{label}: remote script execution patterns such as curl|bash, curl|python, or wget|sh are not allowed"
    return
  end

  has_download = normalized.match?(/\b(curl|wget)\b/i)
  has_interpreter_exec = normalized.match?(/(^|\n)\s*#{script_interpreter_pattern}\b/i)
  if has_download && has_interpreter_exec
    errors << "#{label}: run body combines remote download commands with interpreter execution"
    return
  end

  if normalized.match?(/\b(curl|wget)\b[^\n]*\$/)
    errors << "#{label}: workflow and local action run bodies must not build download URLs dynamically"
    return
  end
end

composite_action_invokes_local_helper = lambda do |label, body|
  normalized = body.to_s.gsub("\r\n", "\n")
  return if normalized.empty?

  if normalized.match?(local_helper_pattern)
    errors << "#{label}: composite local actions must inline commands and must not dispatch to repo-local helper scripts"
  end
end

workflow_files.each do |file|
  begin
    data = Psych.safe_load(File.read(file), permitted_classes: [], permitted_symbols: [], aliases: false, filename: file) || {}
  rescue Psych::Exception => e
    errors << "#{file}: invalid or unsafe YAML: #{e.message}"
    next
  end

  unless data.is_a?(Hash)
    errors << "#{file}: workflow root must be a mapping"
    next
  end

  permissions = data["permissions"]
  trigger_block = data["on"] || data[true]
  basename = File.basename(file)
  expected = expected_permissions[basename]
  expected_jobs = expected_job_permissions.fetch(basename, {})
  expected_pull_request_target_jobs = expected_pull_request_target_conditions[basename]
  jobs = data["jobs"]

  if permissions.nil?
    errors << "#{file}: missing top-level permissions block"
    next
  end

  normalized = validate_permissions_mapping.call(file, permissions)
  next unless normalized

  if expected
    if normalized != expected
      errors << "#{file}: permissions #{normalized.inspect} do not match expected #{expected.inspect}"
    end
  elsif normalized.empty?
    errors << "#{file}: custom workflows must declare at least one explicit top-level permission"
  else
    validate_permissions_against_policy.call(file, normalized, custom_permission_policy)
  end

  unless jobs.is_a?(Hash) && !jobs.empty?
    errors << "#{file}: workflows must define at least one job"
    next
  end

  jobs.each do |job_name, job_data|
    next unless job_data.is_a?(Hash)

    job_permissions = job_data["permissions"]
    expected_job_permissions_for_job = expected_jobs[job_name.to_s]

    if expected
      if expected_job_permissions_for_job
        if job_permissions.nil?
          errors << "#{file}:#{job_name}: missing expected job-level permissions block"
        else
          normalized_job_permissions = validate_permissions_mapping.call("#{file}:#{job_name}", job_permissions)
          if normalized_job_permissions && normalized_job_permissions != expected_job_permissions_for_job
            errors << "#{file}:#{job_name}: permissions #{normalized_job_permissions.inspect} do not match expected #{expected_job_permissions_for_job.inspect}"
          end
        end
      elsif !job_permissions.nil?
        errors << "#{file}:#{job_name}: unexpected job-level permissions block"
      end
    elsif !job_permissions.nil?
      normalized_job_permissions = validate_permissions_mapping.call("#{file}:#{job_name}", job_permissions)
      if normalized_job_permissions
        validate_permissions_against_policy.call("#{file}:#{job_name}", normalized_job_permissions, custom_permission_policy)
        validate_job_permissions_subset.call("#{file}:#{job_name}", normalized, normalized_job_permissions)
      end
    end
  end

  if trigger_block.is_a?(Hash) && trigger_block.key?("pull_request_target")
    unless expected_pull_request_target_jobs
      errors << "#{file}: pull_request_target is only allowed for audited managed workflows"
      next
    end

    jobs.each do |job_name, job_data|
      next unless job_data.is_a?(Hash)

      job_condition = job_data["if"]
      expected_condition = expected_pull_request_target_jobs[job_name.to_s]

      unless expected_condition
        errors << "#{file}:#{job_name}: unexpected job in audited pull_request_target workflow"
        next
      end

      unless job_condition.is_a?(String) && normalize_condition.call(job_condition) == normalize_condition.call(expected_condition)
        errors << "#{file}:#{job_name}: pull_request_target jobs must use the exact audited merge-gating condition"
      end
    end
  end

  jobs.each do |job_name, job_data|
    next unless job_data.is_a?(Hash)
    steps = job_data["steps"]
    next unless steps.is_a?(Array)

    steps.each_with_index do |step, index|
      next unless step.is_a?(Hash)
      next unless step["run"].is_a?(String)

      run_body_executes_remote_code.call("#{file}:#{job_name}:step#{index + 1}", step["run"])
    end
  end
end

action_files.each do |file|
  begin
    data = Psych.safe_load(File.read(file), permitted_classes: [], permitted_symbols: [], aliases: false, filename: file) || {}
  rescue Psych::Exception => e
    errors << "#{file}: invalid or unsafe YAML: #{e.message}"
    next
  end

  unless data.is_a?(Hash)
    errors << "#{file}: action root must be a mapping"
    next
  end

  runs = data["runs"]
  unless runs.is_a?(Hash)
    errors << "#{file}: local actions must define a runs block"
    next
  end

  using = runs["using"].to_s
  unless using == "composite"
    errors << "#{file}: local actions must use runs.using: composite"
    next
  end

  steps = runs["steps"]
  unless steps.is_a?(Array) && !steps.empty?
    errors << "#{file}: composite local actions must define at least one step"
    next
  end

  steps.each_with_index do |step, index|
    next unless step.is_a?(Hash)
    next unless step["run"].is_a?(String)

    run_body_executes_remote_code.call("#{file}:step#{index + 1}", step["run"])
    composite_action_invokes_local_helper.call("#{file}:step#{index + 1}", step["run"])
  end
end

unless errors.empty?
  errors.each { |error| warn(error) }
  exit 1
end
RUBY

audit_yaml_files=("${workflow_files[@]}")
if [ "${#action_files[@]}" -gt 0 ]; then
  audit_yaml_files+=("${action_files[@]}")
fi

declare -a allowed_actions=(
  "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd"
  "actions/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e"
  "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a"
  "actions/attest-build-provenance@a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32"
  "github/codeql-action/upload-sarif@95e58e9a2cdfd71adc6e0353d5c52f41a045d225"
  "ossf/scorecard-action@4eaacf0543bb3f2c246792bd56e8cdeffafb205a"
  "shivammathur/setup-php@accd6127cb78bee3e8082180cb391013d204ef9f"
)

declare -a uses_entries=()
while IFS= read -r entry; do
  uses_entries+=("$entry")
done < <(
  perl -ne '
    if (/^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*([^[:space:]]+)/) {
      print "$ARGV:$.:$1\n";
    }
  ' "${audit_yaml_files[@]}"
)

if [ "${#uses_entries[@]}" -gt 0 ]; then
  for entry in "${uses_entries[@]}"; do
    file="${entry%%:*}"
    rest="${entry#*:}"
    line="${rest%%:*}"
    ref="${entry##*:}"

    if [[ "$ref" == ./* ]]; then
      continue
    fi

    if [[ ! "$ref" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*@[0-9a-f]{40}$ ]]; then
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
fi

declare -a scan_files=()
while IFS= read -r file; do
  case "$file" in
    */scripts/ci/audit_workflows.sh)
      continue
      ;;
    */scripts/foundation/validate.sh|*/scripts/foundation/validate-full.sh|*/scripts/foundation/run_release_update_fixture_checks.sh)
      # These harnesses embed intentionally malicious fixture content in heredocs.
      continue
      ;;
  esac
  scan_files+=("$file")
done < <(find "${scan_dirs[@]}" -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.sh' \) | sort)

remote_script_patterns=(
  'curl[^[:cntrl:]]*\|[[:space:]]*(bash|sh|zsh|dash|ksh|pwsh|python([0-9]+(\.[0-9]+){0,2})?|node(js)?|perl|ruby|php)\b'
  'wget[^[:cntrl:]]*\|[[:space:]]*(bash|sh|zsh|dash|ksh|pwsh|python([0-9]+(\.[0-9]+){0,2})?|node(js)?|perl|ruby|php)\b'
  '(bash|sh|zsh|dash|ksh|pwsh|source|\.|python([0-9]+(\.[0-9]+){0,2})?|node(js)?|perl|ruby|php)[[:space:]]*<\([[:space:]]*(curl|wget)\b'
  '(curl|wget)[^[:cntrl:]]*(&&|;)[^[:cntrl:]]*\b(bash|sh|zsh|dash|ksh|pwsh|source|python([0-9]+(\.[0-9]+){0,2})?|node(js)?|perl|ruby|php)\b'
)

if command -v rg >/dev/null 2>&1; then
  if rg -n \
    -e "${remote_script_patterns[0]}" \
    -e "${remote_script_patterns[1]}" \
    -e "${remote_script_patterns[2]}" \
    -e "${remote_script_patterns[3]}" \
    "${scan_files[@]}" >/dev/null 2>&1; then
    echo "Remote script execution patterns such as curl|bash or wget|sh are not allowed." >&2
    rg -n \
      -e "${remote_script_patterns[0]}" \
      -e "${remote_script_patterns[1]}" \
      -e "${remote_script_patterns[2]}" \
      -e "${remote_script_patterns[3]}" \
      "${scan_files[@]}" >&2
    exit 1
  fi
else
  if grep -nE "${remote_script_patterns[0]}|${remote_script_patterns[1]}|${remote_script_patterns[2]}|${remote_script_patterns[3]}" "${scan_files[@]}" >/dev/null 2>&1; then
    echo "Remote script execution patterns such as curl|bash or wget|sh are not allowed." >&2
    grep -nE "${remote_script_patterns[0]}|${remote_script_patterns[1]}|${remote_script_patterns[2]}|${remote_script_patterns[3]}" "${scan_files[@]}" >&2
    exit 1
  fi
fi

if perl -0ne '
  BEGIN { $failed = 0; }
  my $normalized = $_;
  $normalized =~ s/(?:'\'''\''|"")//g;
  if ($normalized =~ m{\b(?:curl|wget)\b[^\n]*(?:\n[^\n]*){0,5}\n[ \t]*(?:bash|sh|zsh|dash|ksh|pwsh|source|\.|python(?:[0-9]+(?:\.[0-9]+){0,2})?|node(?:js)?|perl|ruby|php)\b}is) {
    print "$ARGV\n";
    $failed = 1;
  }
  END { exit($failed ? 0 : 1); }
' "${scan_files[@]}" >/dev/null 2>&1; then
  echo "Multiline download-then-execute patterns are not allowed in audited scripts or workflow files." >&2
  perl -0ne '
    my $normalized = $_;
    $normalized =~ s/(?:'\'''\''|"")//g;
    if ($normalized =~ m{\b(?:curl|wget)\b[^\n]*(?:\n[^\n]*){0,5}\n[ \t]*(?:bash|sh|zsh|dash|ksh|pwsh|source|\.|python(?:[0-9]+(?:\.[0-9]+){0,2})?|node(?:js)?|perl|ruby|php)\b}is) {
      print "$ARGV\n";
    }
  ' "${scan_files[@]}" >&2
  exit 1
fi

declare -a default_allowed_hosts=(
  'api.github.com'
  'github.com'
  'gitlab.com'
  'uploads.github.com'
  'downloads.wordpress.org'
  'plugins.svn.wordpress.org'
  'woocommerce.com'
  'auth.docker.io'
  'registry-1.docker.io'
  'token.actions.githubusercontent.com'
)

declare -a extra_allowed_hosts=()
if [ -n "${EXTRA_ALLOWED_HOSTS:-}" ]; then
  while IFS= read -r host; do
    host="$(printf '%s' "$host" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$host" ] || continue
    if [[ ! "$host" =~ ^[A-Za-z0-9.-]+$ ]]; then
      echo "Invalid host in EXTRA_ALLOWED_HOSTS: $host" >&2
      exit 1
    fi
    extra_allowed_hosts+=("$host")
  done < <(printf '%s\n' "$EXTRA_ALLOWED_HOSTS" | tr ',' '\n')
fi

host_is_allowlisted() {
  local host="$1"
  local candidate

  for candidate in "${default_allowed_hosts[@]}"; do
    if [ "$host" = "$candidate" ]; then
      return 0
    fi
  done

  if [ "${#extra_allowed_hosts[@]}" -gt 0 ]; then
    for candidate in "${extra_allowed_hosts[@]}"; do
      if [ "$host" = "$candidate" ]; then
        return 0
      fi
    done
  fi

  return 1
}

while IFS=: read -r file line url; do
  [ -n "$url" ] || continue
  host="${url#https://}"
  host="${host#http://}"
  host="${host%%/*}"
  host="${host%%\$\{*}"
  while :; do
    case "$host" in
      *.|*,|*\)|*\]|*\;|*\!|*\?)
        host="${host%?}"
        ;;
      *)
        break
        ;;
    esac
  done
  if ! host_is_allowlisted "$host"; then
    echo "${file}:${line}: URL host is not allowlisted: ${url}" >&2
    if [[ "$host" == gitlab.* ]] || [[ "$host" == *gitlab* ]]; then
      echo "If this is a trusted self-managed GitLab instance, add the host to EXTRA_ALLOWED_HOSTS for workflow-audit allowlisting." >&2
    fi
    exit 1
  fi
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
