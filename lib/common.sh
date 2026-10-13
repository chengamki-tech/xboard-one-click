#!/usr/bin/env bash

# These values are reviewed release inputs. Change them deliberately and record
# the new upstream revision in SECURITY.md before publishing an update.
XBOARD_IMAGE="ghcr.io/cedar2025/xboard@sha256:896e4926e0d7f18d223d58770590c74ab6f05ecb21f1b74ef5357ed20f44c676"
NPM_IMAGE="jc21/nginx-proxy-manager@sha256:4393e642e233e5efd5adeb7f10918d4aaea71c9ed875b94190273fc8e87f9594"
AUDITED_XBOARD_COMMIT="0a749681bb10056bd60ebe9afe4e8928ff19210c"

config_error() {
  printf '[xboard-one-click][WARN] %s\n' "$*" >&2
  return 1
}

load_deploy_env_file() {
  local file="$1"
  local line key value

  [ -f "$file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || {
      config_error "invalid configuration line in $file"
      return 1
    }

    key="${line%%=*}"
    value="${line#*=}"
    [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || {
      config_error "invalid configuration key: $key"
      return 1
    }

    case "$key" in
      NPM_HTTP_PORT|NPM_HTTPS_PORT|NPM_ADMIN_PORT|EXTRA_NPM_HTTPS_PORTS|\
      CLOUD_FIREWALL_PROVIDER|CLOUD_FIREWALL_REGION|CLOUD_FIREWALL_GROUP_ID|\
      CLOUD_FIREWALL_PROJECT_ID|CLOUD_FIREWALL_NETWORK|CLOUD_FIREWALL_TARGET_TAGS|\
      CLOUD_FIREWALL_NSG_ID|CLOUD_FIREWALL_SOURCE_CIDR|CLOUD_FIREWALL_RULE_PREFIX|\
      XBOARD_PORT|XBOARD_ADMIN_EMAIL|XBOARD_REPO|XBOARD_BRANCH|XBOARD_COMMIT|\
      ENABLE_FIREWALL_OPEN|ALLOW_PUBLIC_FIREWALL|FORCE_XBOARD_INSTALL|\
      INTERACTIVE_CONFIG|AUTO_WRITE_DEPLOY_ENV|AUTO_INSTALL_DEPS|SERVER_IP|\
      ALLOW_CUSTOM_XBOARD_SOURCE)
        printf -v "$key" '%s' "$value"
        ;;
      *)
        config_error "unsupported configuration key: $key"
        return 1
        ;;
    esac
  done < "$file"
}

is_valid_https_url() {
  [[ "$1" =~ ^https://[^[:space:]]+$ ]]
}

is_valid_bool() {
  [ "$1" = "0" ] || [ "$1" = "1" ]
}

is_valid_port_value() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

is_valid_cidr_value() {
  local cidr="$1" ip prefix octet
  local -a octets

  [[ "$cidr" == */* ]] || return 1
  ip="${cidr%/*}"
  prefix="${cidr#*/}"
  [[ "$prefix" =~ ^[0-9]+$ ]] && [ "$prefix" -le 32 ] || return 1
  IFS=. read -r -a octets <<< "$ip"
  [ "${#octets[@]}" -eq 4 ] || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]+$ ]] && [ "$octet" -le 255 ] || return 1
  done
}

validate_xboard_source() {
  local repo="${XBOARD_REPO:-}"
  local commit="${XBOARD_COMMIT:-}"

  is_valid_https_url "$repo" || {
    config_error "XBOARD_REPO must use an HTTPS URL"
    return 1
  }
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || {
    config_error "XBOARD_COMMIT must be a 40-character lowercase commit SHA"
    return 1
  }
  [[ "${XBOARD_BRANCH:-}" =~ ^[A-Za-z0-9._/-]+$ && "${XBOARD_BRANCH:-}" != -* && "${XBOARD_BRANCH:-}" != *..* ]] || {
    config_error "XBOARD_BRANCH contains unsupported characters"
    return 1
  }

  if [ "${ALLOW_CUSTOM_XBOARD_SOURCE:-0}" != "1" ] && [ "$repo" != "https://github.com/cedar2025/Xboard" ]; then
    config_error "custom Xboard sources require ALLOW_CUSTOM_XBOARD_SOURCE=1"
    return 1
  fi
  if [ "${ALLOW_CUSTOM_XBOARD_SOURCE:-0}" != "1" ] && [ "$commit" != "$AUDITED_XBOARD_COMMIT" ]; then
    config_error "the audited Xboard commit is fixed; set ALLOW_CUSTOM_XBOARD_SOURCE=1 to override it"
    return 1
  fi
}

validate_boolean_options() {
  local key value
  for key in ENABLE_FIREWALL_OPEN ALLOW_PUBLIC_FIREWALL ALLOW_CUSTOM_XBOARD_SOURCE FORCE_XBOARD_INSTALL; do
    value="${!key:-0}"
    is_valid_bool "$value" || {
      config_error "$key must be 0 or 1"
      return 1
    }
  done
}

validate_firewall_policy() {
  local cidr="${CLOUD_FIREWALL_SOURCE_CIDR:-0.0.0.0/0}"

  is_valid_cidr_value "$cidr" || {
    config_error "CLOUD_FIREWALL_SOURCE_CIDR is invalid: $cidr"
    return 1
  }
  if [ "${ENABLE_FIREWALL_OPEN:-0}" = "1" ] && [ "$cidr" = "0.0.0.0/0" ] && [ "${ALLOW_PUBLIC_FIREWALL:-0}" != "1" ]; then
    config_error "public firewall access requires ALLOW_PUBLIC_FIREWALL=1"
    return 1
  fi
}

pin_xboard_compose_image() {
  local compose_file="$1"

  python3 - "$compose_file" "$XBOARD_IMAGE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
image = sys.argv[2]
text = path.read_text()
pattern = re.compile(r'(?m)^(\s*image:\s*)ghcr\.io/cedar2025/xboard(?::[^\s]+|@sha256:[0-9a-f]{64})\s*$')
text_new, count = pattern.subn(r'\g<1>' + image, text)
if count != 1:
    raise SystemExit(f'expected exactly one Xboard image line in {path}, found {count}')
path.write_text(text_new)
PY
}
