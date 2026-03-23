#!/usr/bin/env bash

set -euo pipefail

VERSION="${1:-}"

if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 vX.Y.Z" >&2
  exit 1
fi

previous_tag="$(
  git tag --sort=-v:refname \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | grep -vx "$VERSION" \
    | head -n 1
)"

if [ -n "$previous_tag" ]; then
  notes="$(git log --no-merges --format='* %s' "${previous_tag}..HEAD")"
else
  notes="$(git log --no-merges --format='* %s')"
fi

if [ -z "$notes" ]; then
  notes="* Maintenance release."
fi

printf '%s\n' "$notes"
