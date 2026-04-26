#!/usr/bin/env bash

set -euo pipefail

DEST_DIR="${1:-}"
TOOL_SELECTION="${2:-all}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHELLCHECK_VERSION='0.11.0'
ACTIONLINT_VERSION='1.7.12'
EDITORCONFIG_CHECKER_VERSION='3.6.1'
GITLEAKS_VERSION='8.30.1'

if [ -z "$DEST_DIR" ]; then
  echo "Usage: $0 <destination-dir> [all|tool1,tool2,...]" >&2
  exit 1
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
      editorconfig_checker_sha256='9c3a046b1f17933b292044645e048764f56f8d687c9c8c7d9c7358153f8e3b65'
      gitleaks_archive="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
      gitleaks_sha256='551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb'
      ;;
    Darwin:x86_64)
      shellcheck_archive="shellcheck-v${SHELLCHECK_VERSION}.darwin.x86_64.tar.xz"
      shellcheck_sha256='3c89db4edcab7cf1c27bff178882e0f6f27f7afdf54e859fa041fca10febe4c6'
      actionlint_archive="actionlint_${ACTIONLINT_VERSION}_darwin_amd64.tar.gz"
      actionlint_sha256='5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644'
      editorconfig_checker_archive='editorconfig-checker-darwin-all.tar.gz'
      editorconfig_checker_sha256='f96c15df363e70dd32e29c911e468e4a5e989ee2a264b562ca52631e8fa5996e'
      gitleaks_archive="gitleaks_${GITLEAKS_VERSION}_darwin_x64.tar.gz"
      gitleaks_sha256='dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709'
      ;;
    Darwin:arm64)
      shellcheck_archive="shellcheck-v${SHELLCHECK_VERSION}.darwin.aarch64.tar.xz"
      shellcheck_sha256='56affdd8de5527894dca6dc3d7e0a99a873b0f004d7aabc30ae407d3f48b0a79'
      actionlint_archive="actionlint_${ACTIONLINT_VERSION}_darwin_arm64.tar.gz"
      actionlint_sha256='aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f'
      editorconfig_checker_archive='editorconfig-checker-darwin-all.tar.gz'
      editorconfig_checker_sha256='f96c15df363e70dd32e29c911e468e4a5e989ee2a264b562ca52631e8fa5996e'
      gitleaks_archive="gitleaks_${GITLEAKS_VERSION}_darwin_arm64.tar.gz"
      gitleaks_sha256='b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5'
      ;;
    *)
      echo "Automatic tool installation is unsupported on ${OS}/${ARCH}. Install the requested binary tools manually." >&2
      exit 1
      ;;
  esac
fi

mkdir -p "$DEST_DIR"
TMP_DIR="$(mktemp -d)"
PYTHON_VENV_DIR="$DEST_DIR/.python-tools-venv"
NODE_TOOLS_DIR="$DEST_DIR/.node-tools"
PIP_CACHE_DIR="$TMP_DIR/pip-cache"
NPM_CACHE_DIR="$TMP_DIR/npm-cache"
PYTHON_LINT_REQUIREMENTS="$ROOT_DIR/tools/python-lint-tools/requirements.txt"
PYTHON_SEMGREP_REQUIREMENTS="$ROOT_DIR/tools/python-semgrep/requirements.txt"
MARKDOWNLINT_TOOLS_DIR="$ROOT_DIR/tools/markdownlint"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

rm -rf "$PYTHON_VENV_DIR"
rm -rf "$NODE_TOOLS_DIR"
mkdir -p "$NODE_TOOLS_DIR"

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
  install "$TMP_DIR/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" "$DEST_DIR/shellcheck"
fi

if tool_requested actionlint; then
  download_file_with_retry "$TMP_DIR/$actionlint_archive" \
    "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/${actionlint_archive}" \
    "actionlint"
  sha256_check "$actionlint_sha256" "$TMP_DIR/$actionlint_archive"
  tar -xzf "$TMP_DIR/$actionlint_archive" -C "$TMP_DIR"
  install "$TMP_DIR/actionlint" "$DEST_DIR/actionlint"
fi

if tool_requested editorconfig-checker; then
  download_file_with_retry "$TMP_DIR/$editorconfig_checker_archive" \
    "https://github.com/editorconfig-checker/editorconfig-checker/releases/download/v${EDITORCONFIG_CHECKER_VERSION}/${editorconfig_checker_archive}" \
    "editorconfig-checker"
  sha256_check "$editorconfig_checker_sha256" "$TMP_DIR/$editorconfig_checker_archive"
  tar -xzf "$TMP_DIR/$editorconfig_checker_archive" -C "$TMP_DIR"
  install "$TMP_DIR/editorconfig-checker" "$DEST_DIR/editorconfig-checker"
fi

if tool_requested gitleaks; then
  download_file_with_retry "$TMP_DIR/$gitleaks_archive" \
    "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${gitleaks_archive}" \
    "gitleaks"
  sha256_check "$gitleaks_sha256" "$TMP_DIR/$gitleaks_archive"
  tar -xzf "$TMP_DIR/$gitleaks_archive" -C "$TMP_DIR"
  install "$TMP_DIR/gitleaks" "$DEST_DIR/gitleaks"
fi

if tool_requested yamllint || tool_requested codespell || tool_requested semgrep; then
  python3 -m venv "$PYTHON_VENV_DIR"

  if tool_requested yamllint || tool_requested codespell; then
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

  if tool_requested semgrep; then
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
fi

if tool_requested markdownlint-cli2; then
  if [ ! -f "$MARKDOWNLINT_TOOLS_DIR/package.json" ] || [ ! -f "$MARKDOWNLINT_TOOLS_DIR/package-lock.json" ]; then
    echo "Committed markdown lint lock files are missing." >&2
    exit 1
  fi

  cp "$MARKDOWNLINT_TOOLS_DIR/package.json" "$NODE_TOOLS_DIR/package.json"
  cp "$MARKDOWNLINT_TOOLS_DIR/package-lock.json" "$NODE_TOOLS_DIR/package-lock.json"
  (
    cd "$NODE_TOOLS_DIR"
    NPM_CONFIG_CACHE="$NPM_CACHE_DIR" npm ci --ignore-scripts --no-audit --no-fund >/dev/null
  )
fi

if tool_requested yamllint; then
  cat > "$DEST_DIR/yamllint" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$PYTHON_VENV_DIR/bin/yamllint" "\$@"
EOF
  chmod +x "$DEST_DIR/yamllint"
fi

if tool_requested semgrep; then
  cat > "$DEST_DIR/semgrep" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$PYTHON_VENV_DIR/bin/semgrep" "\$@"
EOF
  chmod +x "$DEST_DIR/semgrep"
fi

if tool_requested codespell; then
  cat > "$DEST_DIR/codespell" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$PYTHON_VENV_DIR/bin/codespell" "\$@"
EOF
  chmod +x "$DEST_DIR/codespell"
fi

if tool_requested markdownlint-cli2; then
  cat > "$DEST_DIR/markdownlint-cli2" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec node "$NODE_TOOLS_DIR/node_modules/markdownlint-cli2/markdownlint-cli2-bin.mjs" "\$@"
EOF
  chmod +x "$DEST_DIR/markdownlint-cli2"
fi

echo "Installed requested tools into $DEST_DIR"
