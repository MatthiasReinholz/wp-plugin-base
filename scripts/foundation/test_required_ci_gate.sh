#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
# Ruby compares authored GitHub expressions, not shell substitutions.
# shellcheck disable=SC2016
ruby -ryaml -e '
workflow = YAML.safe_load(File.read(ARGV[0]))
concurrency = workflow.fetch("concurrency")
abort "Obsolete CI runs must be cancelled" unless concurrency["cancel-in-progress"] == true
group_for = lambda do |context|
  group = concurrency.fetch("group").gsub(/\$\{\{\s*github\.(\w+)\s*\}\}/) { context.fetch(Regexp.last_match(1)) }
  abort "Concurrency must use simple GitHub context fields" if group.include?("${{")
  group
end
current = { "workflow" => "foundation-ci", "ref" => "refs/pull/123/merge", "sha" => "first-commit" }
key = group_for.call(current)
abort "New PR commits must replace obsolete runs" unless key == group_for.call(current.merge("sha" => "next-commit"))
[
  { "ref" => "refs/pull/456/merge" },
  { "ref" => "refs/heads/main" },
  { "workflow" => "another-workflow" }
].each do |changed_context|
  abort "Independent CI runs must not cancel each other" if key == group_for.call(current.merge(changed_context))
end
jobs = workflow.fetch("jobs")
job = jobs.fetch("validate-strict-local-bootstrap")
prerequisites = ["bootstrap-strict-local", "runtime-wordpress", "validate", "validate-full"]
abort "Required gate check name must remain stable" unless job["name"] == "Validate strict-local bootstrap"
abort "Required gate must run after failed dependencies" unless job["if"] == "${{ always() }}"
abort "Required validation dependency missing" unless job.fetch("needs").sort == prerequisites
(["validate-strict-local-bootstrap"] + prerequisites).each do |name|
  required_job = jobs.fetch(name)
  abort "Required job tolerates errors: #{name}" if required_job["continue-on-error"]
  required_job.fetch("steps").each do |step|
    abort "Required step tolerates errors: #{name}" if step["continue-on-error"]
  end
end
bootstrap = jobs.fetch("bootstrap-strict-local")
abort "Clean bootstrap must run independently" if bootstrap.key?("needs") || bootstrap.key?("if")
[
  "bash scripts/foundation/bootstrap_strict_local.sh",
  "bash scripts/foundation/validate.sh --mode strict-local"
].each do |command|
  step = bootstrap.fetch("steps").find { |entry| entry["run"].to_s.include?(command) }
  abort "Clean bootstrap must run #{command} unconditionally" unless step && !step.key?("if")
end
abort "Required gate must remain a lightweight result check" unless job.fetch("steps").length == 1
step = job.fetch("steps").first
abort "Required result check must run unconditionally" if step.key?("if")
abort "Required gate must inspect real dependency results" unless step.fetch("env").fetch("NEEDS_JSON") == "${{ toJSON(needs) }}"
File.write(ARGV[1], step.fetch("run"))
' "$ROOT_DIR/.github/workflows/foundation-ci.yml" "$fixture/gate.sh"
export NEEDS_JSON
successful_needs='{"validate":{"result":"success"},"validate-full":{"result":"success"},"runtime-wordpress":{"result":"success"},"bootstrap-strict-local":{"result":"success"}}'
NEEDS_JSON="$successful_needs"
bash "$fixture/gate.sh" >/dev/null

assert_rejected() {
  local label="$1"
  if bash "$fixture/gate.sh" >/dev/null 2>&1; then
    echo "Required CI gate accepted $label." >&2
    exit 1
  fi
}

for prerequisite in validate validate-full runtime-wordpress bootstrap-strict-local; do
  for result in failure cancelled skipped; do
    NEEDS_JSON="$(jq --arg prerequisite "$prerequisite" --arg result "$result" '.[$prerequisite].result = $result' <<< "$successful_needs")"
    assert_rejected "$prerequisite with result $result"
  done
  NEEDS_JSON="$(jq --arg prerequisite "$prerequisite" 'del(.[$prerequisite])' <<< "$successful_needs")"
  assert_rejected "missing $prerequisite"
  NEEDS_JSON="$(jq --arg prerequisite "$prerequisite" 'del(.[$prerequisite].result)' <<< "$successful_needs")"
  assert_rejected "missing result for $prerequisite"
done
NEEDS_JSON='{}'
assert_rejected 'missing dependency results'
NEEDS_JSON="$(jq '.extra = {"result":"success"}' <<< "$successful_needs")"
assert_rejected 'unexpected dependency results'
NEEDS_JSON="$(jq '.extra = .["bootstrap-strict-local"] | del(.["bootstrap-strict-local"])' <<< "$successful_needs")"
assert_rejected 'an unrelated successful job in place of clean bootstrap'
NEEDS_JSON='invalid JSON'
assert_rejected 'malformed dependency results'
echo 'Required CI gate enforces independent strict bootstrap and rejects failed, cancelled, skipped, missing or unexpected prerequisites.'
