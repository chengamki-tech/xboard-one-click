#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local needle="$1"
  local file="$2"
  grep -Fq -- "$needle" "$file" || fail "${file} does not contain: ${needle}"
}

test_shell_syntax() {
  local file
  while IFS= read -r file; do
    bash -n "$file"
  done < <(find "$ROOT_DIR" -maxdepth 2 -type f -name '*.sh' -print)
}

test_config_is_data_not_code() {
  local tmp_dir marker
  tmp_dir="$(mktemp -d)"
  marker="$tmp_dir/marker"
  trap 'rm -rf "$tmp_dir"' RETURN

  cp -a "$ROOT_DIR"/. "$tmp_dir/"
  printf 'XBOARD_REPO=$(touch %q)\n' "$marker" > "$tmp_dir/deploy.env"

  if AUTO_INSTALL_DEPS=0 "$tmp_dir/install.sh" --non-interactive >"$tmp_dir/output" 2>&1; then
    fail 'malicious configuration unexpectedly completed'
  fi

  [ ! -e "$marker" ] || fail 'configuration executed shell command substitution'
  assert_contains 'XBOARD_REPO must use an HTTPS URL' "$tmp_dir/output"
}

test_pinned_defaults() {
  assert_contains 'ghcr.io/cedar2025/xboard@sha256:' "$ROOT_DIR/lib/common.sh"
  assert_contains 'jc21/nginx-proxy-manager@sha256:' "$ROOT_DIR/lib/common.sh"
  assert_contains 'XBOARD_COMMIT=' "$ROOT_DIR/deploy.env.example"
  assert_contains 'ENABLE_FIREWALL_OPEN=0' "$ROOT_DIR/deploy.env.example"
  ! rg -n 'image: (ghcr.io/cedar2025/xboard|jc21/nginx-proxy-manager):latest' "$ROOT_DIR" --glob '*.sh' --glob '*.yaml' || fail 'floating image tag remains'
}

test_generated_compose_is_pinned() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  # Source only after scripts expose their functions without running main.
  source "$ROOT_DIR/install.sh"
  NPM_DIR="$tmp_dir/npm"
  XBOARD_DIR="$tmp_dir/xboard"
  NPM_HTTP_PORT=8080
  NPM_HTTPS_PORT=8443
  NPM_ADMIN_PORT=20881
  XBOARD_PORT=27001
  EXTRA_NPM_HTTPS_PORTS='9443'
  mkdir -p "$NPM_DIR" "$XBOARD_DIR"

  write_npm_compose
  ensure_xboard_port_mapping

  assert_contains 'jc21/nginx-proxy-manager@sha256:' "$NPM_DIR/compose.yaml"
  assert_contains 'ghcr.io/cedar2025/xboard@sha256:' "$XBOARD_DIR/compose.override.yaml"
  assert_contains '27001:7001' "$XBOARD_DIR/compose.override.yaml"
  ! rg -n ':latest' "$NPM_DIR/compose.yaml" "$XBOARD_DIR/compose.override.yaml" || fail 'generated compose contains latest'
}

test_firewall_and_boolean_policy() {
  source "$ROOT_DIR/install.sh"
  XBOARD_REPO='https://github.com/cedar2025/Xboard'
  XBOARD_BRANCH='compose'
  XBOARD_COMMIT="$AUDITED_XBOARD_COMMIT"
  ALLOW_CUSTOM_XBOARD_SOURCE=0
  ENABLE_FIREWALL_OPEN=1
  ALLOW_PUBLIC_FIREWALL=0
  CLOUD_FIREWALL_SOURCE_CIDR='0.0.0.0/0'

  if validate_firewall_policy; then
    fail 'public firewall policy was accepted without explicit opt-in'
  fi
  ENABLE_FIREWALL_OPEN=0
  validate_boolean_options
}

test_shell_syntax
test_config_is_data_not_code
test_pinned_defaults
test_generated_compose_is_pinned
test_firewall_and_boolean_policy
printf 'PASS: script security regression tests\n'
