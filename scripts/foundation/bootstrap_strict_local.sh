#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOOLS_DIR="$ROOT_DIR/.wp-plugin-base-tools"
RUN_VALIDATION="${WP_PLUGIN_BASE_BOOTSTRAP_RUN_VALIDATION:-false}"
RUN_FULL_VALIDATION="${WP_PLUGIN_BASE_BOOTSTRAP_RUN_FULL_VALIDATION:-false}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --validate)
      RUN_VALIDATION=true
      shift
      ;;
    --validate-full)
      RUN_FULL_VALIDATION=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [tools-dir] [--validate] [--validate-full]" >&2
      exit 0
      ;;
    *)
      TOOLS_DIR="$1"
      shift
      ;;
  esac
done

bash "$ROOT_DIR/scripts/ci/install_lint_tools.sh" "$TOOLS_DIR"
bash "$ROOT_DIR/scripts/release/install_release_security_tools.sh" "$TOOLS_DIR"

missing_tools=()
for required_tool in shellcheck actionlint editorconfig-checker gitleaks yamllint markdownlint-cli2 codespell syft cosign; do
  if [ ! -x "$TOOLS_DIR/$required_tool" ]; then
    missing_tools+=("$required_tool")
  fi
done

if [ "${#missing_tools[@]}" -gt 0 ]; then
  echo "Strict-local bootstrap did not install all required tools:" >&2
  printf '  %s\n' "${missing_tools[@]}" >&2
  exit 1
fi

echo
printf 'Installed strict-local foundation tools into: %s\n' "$TOOLS_DIR"
printf 'Add to current shell PATH before strict-local validation:\n'
printf '  export PATH="%s:$PATH"\n' "$TOOLS_DIR"
printf 'A+ local acceptance command:\n'
printf '  bash scripts/foundation/bootstrap_strict_local.sh "%s" --validate-full\n' "$TOOLS_DIR"

if [ "$RUN_VALIDATION" = 'true' ]; then
  PATH="$TOOLS_DIR:$PATH" bash "$ROOT_DIR/scripts/foundation/validate.sh" --mode strict-local
fi

if [ "$RUN_FULL_VALIDATION" = 'true' ]; then
  PATH="$TOOLS_DIR:$PATH" bash "$ROOT_DIR/scripts/foundation/validate-full.sh" --mode strict-local
fi
