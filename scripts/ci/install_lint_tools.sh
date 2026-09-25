#!/usr/bin/env bash

set -euo pipefail

DEST_DIR="${1:-}"
TOOL_SELECTION="${2-all}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHELLCHECK_VERSION='0.11.0'
ACTIONLINT_VERSION='1.7.12'
EDITORCONFIG_CHECKER_VERSION='3.11.3'
GITLEAKS_VERSION='8.30.1'

if [ -z "$DEST_DIR" ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <destination-dir> [all|tool1,tool2,...]" >&2
  exit 1
fi

# Reject typos and empty entries before creating or changing the destination.
if [ "$TOOL_SELECTION" != all ]; then
  case "$TOOL_SELECTION" in
    ''|,*|*,|*,,*|*[[:space:]]*)
      echo "Tool selection must be a non-empty comma-separated list." >&2
      exit 1
      ;;
  esac
  IFS=',' read -r -a selected_tools <<< "$TOOL_SELECTION"
  for selected_tool in "${selected_tools[@]}"; do
    case "$selected_tool" in
      shellcheck|actionlint|editorconfig-checker|gitleaks|yamllint|codespell|semgrep|markdownlint-cli2) ;;
      *)
        echo "Unknown tool selection: $selected_tool" >&2
        exit 1
        ;;
    esac
  done
fi

OS="${WP_PLUGIN_BASE_INSTALL_TOOLS_OS:-$(uname -s)}"
ARCH="${WP_PLUGIN_BASE_INSTALL_TOOLS_ARCH:-$(uname -m)}"

shellcheck_archive=''
shellcheck_sha256=''
actionlint_archive=''
actionlint_sha256=''
editorconfig_checker_archive=''
editorconfig_checker_sha256=''
gitleaks_archive=''
gitleaks_sha256=''

tool_requested() {
  local tool="$1"

  if [ "$TOOL_SELECTION" = "all" ]; then
    if [ "$tool" = "semgrep" ]; then
      return 1
    fi
    return 0
  fi

  case ",$TOOL_SELECTION," in
    *",$tool,"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

needs_binary_tools=false
for binary_tool in shellcheck actionlint editorconfig-checker gitleaks; do
  if tool_requested "$binary_tool"; then
    needs_binary_tools=true
    break
  fi
done

if [ "$needs_binary_tools" = true ]; then
  case "${OS}:${ARCH}" in
    Linux:x86_64)
      shellcheck_archive="shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz"
      shellcheck_sha256='8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198'
      actionlint_archive="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
      actionlint_sha256='8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8'
      editorconfig_checker_archive='editorconfig-checker-linux-amd64.tar.gz'
      editorconfig_checker_sha256='7b7c828bd4bd7976f66d91f288cb1319b5f27c7fb5faa6b8cca9a0a7ff182578'
      gitleaks_archive="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
      gitleaks_sha256='551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb'
      ;;
    Darwin:x86_64)
      shellcheck_archive="shellcheck-v${SHELLCHECK_VERSION}.darwin.x86_64.tar.xz"
      shellcheck_sha256='3c89db4edcab7cf1c27bff178882e0f6f27f7afdf54e859fa041fca10febe4c6'
      actionlint_archive="actionlint_${ACTIONLINT_VERSION}_darwin_amd64.tar.gz"
      actionlint_sha256='5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644'
      editorconfig_checker_archive='editorconfig-checker-darwin-all.tar.gz'
      editorconfig_checker_sha256='bc697c4d5b3596e4d8c6c1b5627e43700d7fca7b1a418bf1d0ea64c9a85c831c'
      gitleaks_archive="gitleaks_${GITLEAKS_VERSION}_darwin_x64.tar.gz"
      gitleaks_sha256='dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709'
      ;;
    Darwin:arm64)
      shellcheck_archive="shellcheck-v${SHELLCHECK_VERSION}.darwin.aarch64.tar.xz"
      shellcheck_sha256='56affdd8de5527894dca6dc3d7e0a99a873b0f004d7aabc30ae407d3f48b0a79'
      actionlint_archive="actionlint_${ACTIONLINT_VERSION}_darwin_arm64.tar.gz"
      actionlint_sha256='aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f'
      editorconfig_checker_archive='editorconfig-checker-darwin-all.tar.gz'
      editorconfig_checker_sha256='bc697c4d5b3596e4d8c6c1b5627e43700d7fca7b1a418bf1d0ea64c9a85c831c'
      gitleaks_archive="gitleaks_${GITLEAKS_VERSION}_darwin_arm64.tar.gz"
      gitleaks_sha256='b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5'
      ;;
    *)
      echo "Automatic tool installation is unsupported on ${OS}/${ARCH}. Install the requested binary tools manually." >&2
      exit 1
      ;;
  esac
fi

python_tool_enabled() {
  tool_requested "$1" || [ -f "$DEST_DIR/$1" ]
}

needs_python_tools=false
if tool_requested yamllint || tool_requested codespell || tool_requested semgrep; then
  needs_python_tools=true
fi

for selected_tool in shellcheck actionlint editorconfig-checker gitleaks yamllint codespell semgrep markdownlint-cli2; do
  if tool_requested "$selected_tool" || { [ "$needs_python_tools" = true ] && python_tool_enabled "$selected_tool"; }; then
    if [ -d "$DEST_DIR/$selected_tool" ]; then
      echo "Tool executable path is a directory: $DEST_DIR/$selected_tool" >&2
      exit 1
    fi
  fi
done

mkdir -p "$DEST_DIR"
DEST_DIR="$(cd "$DEST_DIR" && pwd -P)"
# Keep staged wrappers on the destination filesystem for atomic rename.
TMP_DIR="$(mktemp -d "$DEST_DIR/.tool-install.XXXXXXXX")"
PYTHON_VENV_DIR=''
NODE_TOOLS_DIR=''
PYTHON_ACTIVATED=false
NODE_ACTIVATED=false
PIP_CACHE_DIR="$TMP_DIR/pip-cache"
NPM_CACHE_DIR="$TMP_DIR/npm-cache"
PYTHON_LINT_REQUIREMENTS="$ROOT_DIR/tools/python-lint-tools/requirements.txt"
PYTHON_SEMGREP_REQUIREMENTS="$ROOT_DIR/tools/python-semgrep/requirements.txt"
MARKDOWNLINT_TOOLS_DIR="$ROOT_DIR/tools/markdownlint"

cleanup() {
  rm -rf "$TMP_DIR"
  if [ -n "$PYTHON_VENV_DIR" ] && [ "$PYTHON_ACTIVATED" = false ]; then
    rm -rf "$PYTHON_VENV_DIR"
  fi
  if [ -n "$NODE_TOOLS_DIR" ] && [ "$NODE_ACTIVATED" = false ]; then
    rm -rf "$NODE_TOOLS_DIR"
  fi
}

trap cleanup EXIT

mkdir -p "$TMP_DIR/wrappers"

stage_wrapper() {
  local tool="$1"
  shift
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\nexec'
    printf ' %q' "$@"
    printf ' "$@"\n'
  } > "$TMP_DIR/wrappers/$tool"
  chmod +x "$TMP_DIR/wrappers/$tool"
}

sha256_check() {
  local expected="$1"
  local file="$2"

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s  %s\n' "$expected" "$file" | sha256sum -c -
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    printf '%s  %s\n' "$expected" "$file" | shasum -a 256 -c -
    return 0
  fi

  echo "No SHA-256 verification tool available." >&2
  exit 1
}

download_file_with_retry() {
  local output_path="$1"
  local url="$2"
  local label="$3"
  local attempts="${WP_PLUGIN_BASE_TOOL_DOWNLOAD_RETRIES:-5}"
  local delay="${WP_PLUGIN_BASE_TOOL_DOWNLOAD_RETRY_DELAY_SECONDS:-2}"
  local attempt=1

  if ! [[ "$attempts" =~ ^[1-9][0-9]*$ ]]; then
    echo "Tool download retry count must be a positive integer: $attempts" >&2
    exit 1
  fi
  if ! [[ "$delay" =~ ^[0-9]+$ ]]; then
    echo "Tool download retry delay must be a non-negative integer: $delay" >&2
    exit 1
  fi

  while [ "$attempt" -le "$attempts" ]; do
    if curl -fsSLo "$output_path" "$url"; then
      return 0
    fi

    rm -f "$output_path"
    if [ "$attempt" -eq "$attempts" ]; then
      echo "Failed to download $label after $attempts attempt(s): $url" >&2
      return 1
    fi

    echo "Download failed for $label on attempt ${attempt}/${attempts}; retrying in ${delay}s." >&2
    sleep "$delay"
    attempt=$((attempt + 1))
  done
}

if tool_requested shellcheck; then
  download_file_with_retry "$TMP_DIR/$shellcheck_archive" \
    "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${shellcheck_archive}" \
    "shellcheck"
  sha256_check "$shellcheck_sha256" "$TMP_DIR/$shellcheck_archive"
  tar -xJf "$TMP_DIR/$shellcheck_archive" -C "$TMP_DIR"
  install "$TMP_DIR/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "$TMP_DIR/wrappers/shellcheck"
fi

if tool_requested actionlint; then
  download_file_with_retry "$TMP_DIR/$actionlint_archive" \
    "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/${actionlint_archive}" \
    "actionlint"
  sha256_check "$actionlint_sha256" "$TMP_DIR/$actionlint_archive"
  tar -xzf "$TMP_DIR/$actionlint_archive" -C "$TMP_DIR"
  install "$TMP_DIR/actionlint" "$TMP_DIR/wrappers/actionlint"
fi

if tool_requested editorconfig-checker; then
  download_file_with_retry "$TMP_DIR/$editorconfig_checker_archive" \
    "https://github.com/editorconfig-checker/editorconfig-checker/releases/download/v${EDITORCONFIG_CHECKER_VERSION}/${editorconfig_checker_archive}" \
    "editorconfig-checker"
  sha256_check "$editorconfig_checker_sha256" "$TMP_DIR/$editorconfig_checker_archive"
  tar -xzf "$TMP_DIR/$editorconfig_checker_archive" -C "$TMP_DIR"
  install "$TMP_DIR/editorconfig-checker" "$TMP_DIR/wrappers/editorconfig-checker"
fi

if tool_requested gitleaks; then
  download_file_with_retry "$TMP_DIR/$gitleaks_archive" \
    "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${gitleaks_archive}" \
    "gitleaks"
  sha256_check "$gitleaks_sha256" "$TMP_DIR/$gitleaks_archive"
  tar -xzf "$TMP_DIR/$gitleaks_archive" -C "$TMP_DIR"
  install "$TMP_DIR/gitleaks" "$TMP_DIR/wrappers/gitleaks"
fi

if [ "$needs_python_tools" = true ]; then
  # Virtualenv scripts embed this exact path. Build in its permanent location;
  # only the small executable wrappers are moved when installation succeeds.
  PYTHON_VENV_DIR="$(mktemp -d "$DEST_DIR/.python-tools-venv.XXXXXXXX")"
  python3 -m venv "$PYTHON_VENV_DIR"

  if python_tool_enabled yamllint || python_tool_enabled codespell; then
    if [ ! -f "$PYTHON_LINT_REQUIREMENTS" ]; then
      echo "Committed Python lint tool lock file is missing." >&2
      exit 1
    fi
    "$PYTHON_VENV_DIR/bin/python" -m pip install \
      --disable-pip-version-check \
      --no-input \
      --cache-dir "$PIP_CACHE_DIR" \
      --require-hashes \
      -r "$PYTHON_LINT_REQUIREMENTS" >/dev/null
  fi

  if python_tool_enabled semgrep; then
    if [ ! -f "$PYTHON_SEMGREP_REQUIREMENTS" ]; then
      echo "Committed Semgrep lock file is missing." >&2
      exit 1
    fi
    "$PYTHON_VENV_DIR/bin/python" -m pip install \
      --disable-pip-version-check \
      --no-input \
      --cache-dir "$PIP_CACHE_DIR" \
      --require-hashes \
      -r "$PYTHON_SEMGREP_REQUIREMENTS" >/dev/null
  fi
  "$PYTHON_VENV_DIR/bin/python" -m pip check >/dev/null
  for selected_tool in yamllint codespell semgrep; do
    if python_tool_enabled "$selected_tool"; then
      if [ ! -x "$PYTHON_VENV_DIR/bin/$selected_tool" ]; then
        echo "Python installation is missing executable: $selected_tool" >&2
        exit 1
      fi
      stage_wrapper "$selected_tool" "$PYTHON_VENV_DIR/bin/$selected_tool"
    fi
  done
fi

if tool_requested markdownlint-cli2; then
  if [ ! -f "$MARKDOWNLINT_TOOLS_DIR/package.json" ] || [ ! -f "$MARKDOWNLINT_TOOLS_DIR/package-lock.json" ]; then
    echo "Committed markdown lint lock files are missing." >&2
    exit 1
  fi

  NODE_TOOLS_DIR="$(mktemp -d "$DEST_DIR/.node-tools.XXXXXXXX")"
  cp "$MARKDOWNLINT_TOOLS_DIR/package.json" "$NODE_TOOLS_DIR/package.json"
  cp "$MARKDOWNLINT_TOOLS_DIR/package-lock.json" "$NODE_TOOLS_DIR/package-lock.json"
  (
    cd "$NODE_TOOLS_DIR"
    NPM_CONFIG_CACHE="$NPM_CACHE_DIR" npm ci --ignore-scripts --no-audit --no-fund >/dev/null
  )
  if [ ! -f "$NODE_TOOLS_DIR/node_modules/markdownlint-cli2/markdownlint-cli2-bin.mjs" ]; then
    echo "Node installation is missing markdownlint-cli2." >&2
    exit 1
  fi
  stage_wrapper markdownlint-cli2 node "$NODE_TOOLS_DIR/node_modules/markdownlint-cli2/markdownlint-cli2-bin.mjs"
fi

# Do not delete prior environments: an existing process may still import from
# them. If activation is interrupted, both old and new wrappers remain usable.
for wrapper in "$TMP_DIR/wrappers/"*; do
  case "$(basename "$wrapper")" in
    yamllint|codespell|semgrep) PYTHON_ACTIVATED=true ;;
    markdownlint-cli2) NODE_ACTIVATED=true ;;
  esac
  mv -f "$wrapper" "$DEST_DIR/$(basename "$wrapper")"
done

echo "Installed requested tools into $DEST_DIR"
