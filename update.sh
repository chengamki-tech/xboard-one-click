#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="xboard-one-click-update"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

WORK_DIR="${SCRIPT_DIR}/runtime"
NPM_DIR="${WORK_DIR}/nginx-proxy-manager"
XBOARD_DIR="${WORK_DIR}/Xboard"
DEPLOY_ENV_FILE="${SCRIPT_DIR}/deploy.env"

DEFAULT_XBOARD_BRANCH="compose"
DEFAULT_NPM_HTTP_PORT=80
DEFAULT_NPM_HTTPS_PORT=443
DEFAULT_NPM_ADMIN_PORT=81
DEFAULT_XBOARD_PORT=7001
DEFAULT_XBOARD_REPO="https://github.com/cedar2025/Xboard"
DEFAULT_XBOARD_COMMIT="$AUDITED_XBOARD_COMMIT"

INPUT_NPM_HTTP_PORT="${NPM_HTTP_PORT:-}"
INPUT_NPM_HTTPS_PORT="${NPM_HTTPS_PORT:-}"
INPUT_NPM_ADMIN_PORT="${NPM_ADMIN_PORT:-}"
INPUT_EXTRA_NPM_HTTPS_PORTS="${EXTRA_NPM_HTTPS_PORTS:-}"
INPUT_XBOARD_BRANCH="${XBOARD_BRANCH:-}"
INPUT_XBOARD_PORT="${XBOARD_PORT:-}"
INPUT_XBOARD_REPO="${XBOARD_REPO:-}"
INPUT_XBOARD_COMMIT="${XBOARD_COMMIT:-}"

NPM_HTTP_PORT="${NPM_HTTP_PORT:-}"
NPM_HTTPS_PORT="${NPM_HTTPS_PORT:-}"
NPM_ADMIN_PORT="${NPM_ADMIN_PORT:-}"
EXTRA_NPM_HTTPS_PORTS="${EXTRA_NPM_HTTPS_PORTS:-}"
XBOARD_BRANCH="${XBOARD_BRANCH:-}"
XBOARD_PORT="${XBOARD_PORT:-}"
XBOARD_REPO="${XBOARD_REPO:-}"
XBOARD_COMMIT="${XBOARD_COMMIT:-}"
COMPOSE_CMD=()

log() {
  printf '[%s] %s\n' "$PROJECT_NAME" "$*"
}

die() {
  printf '[%s][WARN] %s\n' "$PROJECT_NAME" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

run_compose() {
  local dir="$1"
  shift
  (cd "$dir" && "${COMPOSE_CMD[@]}" "$@")
}

normalize_port_csv() {
  printf '%s' "$1" | tr ', ' '\n\n' | awk 'NF && !seen[$0]++ {printf("%s%s", sep, $0); sep=","}'
}

extra_https_ports_to_array() {
  local normalized
  normalized="$(normalize_port_csv "$EXTRA_NPM_HTTPS_PORTS")"
  EXTRA_NPM_HTTPS_PORTS="$normalized"

  if [ -n "$normalized" ]; then
    IFS=',' read -r -a EXTRA_HTTPS_PORTS_ARRAY <<< "$normalized"
  else
    EXTRA_HTTPS_PORTS_ARRAY=()
  fi
}

install_menu_shortcut() {
  local target="/usr/local/bin/xb"

  if [ ! -f "$SCRIPT_DIR/menu.sh" ]; then
    log "未找到 menu.sh，跳过安装 xb 快捷命令"
    return 0
  fi

  cat >"$target" <<EOF
#!/usr/bin/env bash
exec bash "${SCRIPT_DIR}/menu.sh" "\$@"
EOF
  chmod +x "$target"

  log "已安装快捷命令: xb -> ${SCRIPT_DIR}/menu.sh"
}

load_deploy_env() {
  if [ -f "$DEPLOY_ENV_FILE" ]; then
    log "加载本地配置文件: $DEPLOY_ENV_FILE"
    load_deploy_env_file "$DEPLOY_ENV_FILE"
  fi

  [ -z "$INPUT_NPM_HTTP_PORT" ] || NPM_HTTP_PORT="$INPUT_NPM_HTTP_PORT"
  [ -z "$INPUT_NPM_HTTPS_PORT" ] || NPM_HTTPS_PORT="$INPUT_NPM_HTTPS_PORT"
  [ -z "$INPUT_NPM_ADMIN_PORT" ] || NPM_ADMIN_PORT="$INPUT_NPM_ADMIN_PORT"
  [ -z "$INPUT_EXTRA_NPM_HTTPS_PORTS" ] || EXTRA_NPM_HTTPS_PORTS="$INPUT_EXTRA_NPM_HTTPS_PORTS"
  [ -z "$INPUT_XBOARD_BRANCH" ] || XBOARD_BRANCH="$INPUT_XBOARD_BRANCH"
  [ -z "$INPUT_XBOARD_PORT" ] || XBOARD_PORT="$INPUT_XBOARD_PORT"
  [ -z "$INPUT_XBOARD_REPO" ] || XBOARD_REPO="$INPUT_XBOARD_REPO"
  [ -z "$INPUT_XBOARD_COMMIT" ] || XBOARD_COMMIT="$INPUT_XBOARD_COMMIT"
}

apply_defaults() {
  NPM_HTTP_PORT="${NPM_HTTP_PORT:-${DEFAULT_NPM_HTTP_PORT}}"
  NPM_HTTPS_PORT="${NPM_HTTPS_PORT:-${DEFAULT_NPM_HTTPS_PORT}}"
  NPM_ADMIN_PORT="${NPM_ADMIN_PORT:-${DEFAULT_NPM_ADMIN_PORT}}"
  EXTRA_NPM_HTTPS_PORTS="${EXTRA_NPM_HTTPS_PORTS:-}"
  XBOARD_BRANCH="${XBOARD_BRANCH:-${DEFAULT_XBOARD_BRANCH}}"
  XBOARD_PORT="${XBOARD_PORT:-${DEFAULT_XBOARD_PORT}}"
  XBOARD_REPO="${XBOARD_REPO:-${DEFAULT_XBOARD_REPO}}"
  XBOARD_COMMIT="${XBOARD_COMMIT:-${DEFAULT_XBOARD_COMMIT}}"
  CLOUD_FIREWALL_SOURCE_CIDR="${CLOUD_FIREWALL_SOURCE_CIDR:-0.0.0.0/0}"
}

write_npm_compose() {
  extra_https_ports_to_array

  {
    cat <<EOF
services:
  app:
    image: ${NPM_IMAGE}
    restart: unless-stopped
    ports:
      - "${NPM_HTTP_PORT}:80"
      - "${NPM_HTTPS_PORT}:443"
      - "${NPM_ADMIN_PORT}:81"
EOF

    if [ ${#EXTRA_HTTPS_PORTS_ARRAY[@]} -gt 0 ]; then
      local port
      for port in "${EXTRA_HTTPS_PORTS_ARRAY[@]}"; do
        printf '      - "%s:443"\n' "$port"
      done
    fi

    cat <<EOF
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF
  } >"$NPM_DIR/compose.yaml"
}

check_env() {
  need_cmd git
  need_cmd docker
  need_cmd python3

  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
  else
    die "未找到 docker compose / docker-compose"
  fi

  docker info >/dev/null 2>&1 || die "当前用户无法访问 Docker daemon。"
}

ensure_xboard_port_mapping() {
  cat >"$XBOARD_DIR/compose.override.yaml" <<EOF
services:
  xboard:
    image: ${XBOARD_IMAGE}
    ports:
      - "${XBOARD_PORT}:7001"
EOF

  grep -Fq "\"${XBOARD_PORT}:7001\"" "$XBOARD_DIR/compose.override.yaml" || die "Xboard Compose 覆盖配置校验失败"
  log "compose.override.yaml 已固定 Xboard 镜像和端口: ${XBOARD_PORT}:7001"
}

main() {
  load_deploy_env
  apply_defaults
  check_env

  [ -f "$NPM_DIR/compose.yaml" ] || die "未找到 NPM 部署目录，请先执行 ./install.sh"
  [ -d "$XBOARD_DIR/.git" ] || die "未找到 Xboard 运行目录，请先执行 ./install.sh"

  validate_boolean_options || die "布尔配置校验失败"
  validate_xboard_source || die "Xboard 来源校验失败"
  log "按 deploy.env 重写 Nginx Proxy Manager compose 配置"
  write_npm_compose

  log "更新 Nginx Proxy Manager 镜像"
  run_compose "$NPM_DIR" pull
  run_compose "$NPM_DIR" up -d

  log "更新 Xboard 仓库到已审核提交: ${XBOARD_COMMIT}"
  git -C "$XBOARD_DIR" fetch origin "$XBOARD_COMMIT" --depth 1
  git -C "$XBOARD_DIR" checkout --detach "$XBOARD_COMMIT"
  ensure_xboard_port_mapping

  log "更新 Xboard 镜像并重建容器"
  run_compose "$XBOARD_DIR" pull
  run_compose "$XBOARD_DIR" up -d
  run_compose "$XBOARD_DIR" port xboard 7001

  install_menu_shortcut

  log "更新完成（当前 Xboard 对外端口: $XBOARD_PORT）"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
