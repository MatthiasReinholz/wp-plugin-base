#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
cp "$ROOT_DIR/tests/fixtures/standard-plugin/.wp-plugin-base.env" "$fixture/"
export WP_PLUGIN_BASE_ROOT="$fixture"
WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGE="example.invalid/runtime@sha256:$(printf '%064d' 0)"
export WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGE
export WP_PLUGIN_BASE_GITLAB_BOOTSTRAP_APT=false
printf '\nPHP_VERSION=%s\nNODE_VERSION=%s\n' "$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')" "$(node -p 'process.versions.node.split(".")[0]')" >> "$fixture/.wp-plugin-base.env"
bash "$ROOT_DIR/scripts/ci/prepare_gitlab_runtime.sh" > "$fixture/runtime.log"
bash "$ROOT_DIR/scripts/ci/generate_gitlab_runtime_pipeline.sh" > "$fixture/disabled.yml"
ruby -ryaml -e 'job = YAML.safe_load(File.read(ARGV[0]), aliases: true).fetch("runtime-matrix-disabled"); abort "Disabled matrix needs its own pinned image" unless job.fetch("image") == ENV.fetch("WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGE")' "$fixture/disabled.yml"
printf '\nPHP_RUNTIME_MATRIX=8.2,8.5\n' >> "$fixture/.wp-plugin-base.env"
if bash "$ROOT_DIR/scripts/ci/generate_gitlab_runtime_pipeline.sh" > "$fixture/pipeline.yml" 2> "$fixture/error.log"; then
  echo 'Runtime matrix accepted missing pinned image mappings.' >&2
  exit 1
fi
export WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGES="{\"8.2\":\"$WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGE\",\"8.5\":\"$WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGE\"}"
bash "$ROOT_DIR/scripts/ci/generate_gitlab_runtime_pipeline.sh" > "$fixture/pipeline.yml"
ruby -ryaml -e 'doc = YAML.safe_load(File.read(ARGV[0]), aliases: true); abort "Missing runtime jobs" unless doc.keys.sort == ["runtime-php-8.2", "runtime-php-8.5", "stages"]; doc.each { |key, job| next if key == "stages"; abort "Missing runtime verification" unless job["script"].first.include?("prepare_gitlab_runtime.sh") }' "$fixture/pipeline.yml"
export WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGE=example.invalid/runtime:latest
if bash "$ROOT_DIR/scripts/ci/prepare_gitlab_runtime.sh" >/dev/null 2>&1; then
  echo 'Runtime accepted mutable image tag.' >&2
  exit 1
fi
WP_PLUGIN_BASE_GITLAB_RUNTIME_IMAGE="example.invalid/runtime@sha256:$(printf '%064d' 0)"
export WP_PLUGIN_BASE_EXPECTED_PHP_VERSION=0.0
if bash "$ROOT_DIR/scripts/ci/prepare_gitlab_runtime.sh" > "$fixture/runtime.log" 2>&1; then
  echo 'Runtime accepted the wrong PHP version.' >&2
  exit 1
fi
grep -Fq 'runtime mismatch' "$fixture/runtime.log"
ruby -ryaml -e 'doc = YAML.safe_load(File.read(ARGV[0]), aliases: true); rules = doc.fetch(".wp_plugin_base_runtime").fetch("rules"); abort "MR runtime checks omitted" unless rules.any? { |rule| rule["if"].include?("merge_request_event") }; abort "Matrix trigger omits MR" unless doc.fetch("runtime_matrix").fetch("rules") == rules; abort "Tag history shallow" unless doc.fetch("variables").fetch("GIT_DEPTH") == "0"' "$ROOT_DIR/templates/child/.gitlab-ci.yml"
echo 'GitLab runtime versions and matrix image contracts passed.'
