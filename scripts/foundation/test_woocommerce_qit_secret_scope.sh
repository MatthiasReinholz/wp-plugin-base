#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

fixture="$(mktemp -d)"
helper_dir="$(mktemp -d)"
log_file="$(mktemp)"

cleanup() {
  rm -rf "$fixture" "$helper_dir" "$log_file"
}
trap cleanup EXIT

cat > "$fixture/.wp-plugin-base.env" <<'EOF'
PLUGIN_SLUG=standard-plugin
EOF

mkdir -p "$helper_dir/bin"
cat > "$helper_dir/bin/composer" <<'EOF'
#!/usr/bin/env bash
if [ -n "${QIT_USER:-}" ] || [ -n "${QIT_APP_PASSWORD:-}" ]; then
  echo "Composer received QIT credentials." >&2
  exit 1
fi

args=" $* "
if [[ "$args" != *" --no-scripts "* ]] || [[ "$args" != *" --no-plugins "* ]]; then
  echo "Composer install did not disable scripts and plugins: $*" >&2
  exit 1
fi

printf 'composer\t%s\n' "$*" >> "${QIT_SECRET_SCOPE_LOG:?}"
exit 0
EOF
chmod +x "$helper_dir/bin/composer"

cat > "$helper_dir/bin/qit" <<'EOF'
#!/usr/bin/env bash
if [ "${QIT_USER:-}" != "fixture-user" ] || [ "${QIT_APP_PASSWORD:-}" != "fixture-password" ]; then
  echo "QIT invocation did not receive scoped credentials." >&2
  exit 1
fi

printf 'qit\t%s\n' "$*" >> "${QIT_SECRET_SCOPE_LOG:?}"
exit 0
EOF
chmod +x "$helper_dir/bin/qit"

(
  cd "$fixture"
  PATH="$helper_dir/bin:$PATH" \
    WP_PLUGIN_BASE_ROOT="$fixture" \
    QIT_SECRET_SCOPE_LOG="$log_file" \
    QIT_USER="fixture-user" \
    QIT_APP_PASSWORD="fixture-password" \
    bash "$ROOT_DIR/scripts/ci/run_woocommerce_qit.sh" \
      "standard-plugin" \
      "activation, security"
)

grep -Fq 'composer	global require --no-interaction --no-progress --no-scripts --no-plugins woocommerce/qit-cli:1.1.8' "$log_file"
grep -Fq 'qit	run:activation standard-plugin' "$log_file"
grep -Fq 'qit	run:security standard-plugin' "$log_file"

echo "WooCommerce QIT secret scope test passed."
