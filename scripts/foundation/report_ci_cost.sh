#!/usr/bin/env bash

set -euo pipefail
repository="${1:?Usage: report_ci_cost.sh owner/repository run-id}"
run_id="${2:?Usage: report_ci_cost.sh owner/repository run-id}"
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && "$run_id" =~ ^[0-9]+$ ]] || exit 1
gh run view "$run_id" --repo "$repository" --json url,headSha,status,conclusion,createdAt,updatedAt,jobs |
  jq '{url, headSha, status, conclusion, jobs: [.jobs[] | {name, conclusion, seconds: (if .startedAt != null and .completedAt != null and .completedAt != "0001-01-01T00:00:00Z" then ((.completedAt | fromdateiso8601) - (.startedAt | fromdateiso8601)) else null end)}]} | . + {total_job_seconds: ([.jobs[].seconds // 0] | add)}'
