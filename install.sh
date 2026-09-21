#!/usr/bin/env bash
# ============================================================
#  鱼虾蟹 H5 游戏 - 一键部署脚本
#  用法：
#    curl -fsSL <URL>/install.sh | bash
#  或指定安装目录/包地址：
#    bash install.sh /opt/yuxiaxie
#    PKG_URL=http://x/yuxiaxie-docker.tar.gz bash install.sh
#  离线：把 yuxiaxie-docker.tar.gz 和本脚本放同目录，直接 bash install.sh
# ============================================================
set -euo pipefail

APP_DIR="${1:-/opt/yuxiaxie}"
PKG_URL="${PKG_URL:-https://raw.githubusercontent.com/xingcheng1423-cmyk/yuxiaxie-docker/main/yuxiaxie-docker.tar.gz}"
PKG_PARTS="${PKG_PARTS:-https://cdn.jsdelivr.net/gh/xingcheng1423-cmyk/yuxiaxie-docker@main/pkg.b64}"
PKG_PARTS2="${PKG_PARTS2:-https://raw.githubusercontent.com/xingcheng1423-cmyk/yuxiaxie-docker/main/pkg.b64}"
PKG_NAME="yuxiaxie-docker.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo .)"

log()  { printf '\033[32m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

rand() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

# ---------- 1. 检查 root ----------
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
  command -v sudo >/dev/null 2>&1 || die "请用 root 运行：su - 后重新执行"
else
  SUDO=""
fi

# ---------- 2. 检查 / 安装 Docker ----------
ensure_curl() {
  command -v curl >/dev/null 2>&1 && return 0
  warn "未检测到 curl，正在安装..."
  if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update -qq >/dev/null 2>&1 || true
    $SUDO apt-get install -y -qq curl ca-certificates >/dev/null 2>&1 || true
    if ! command -v curl >/dev/null 2>&1; then
      # Debian 已 EOL：官方源 404，切 archive 源重试
      . /etc/os-release 2>/dev/null || true
      C="${VERSION_CODENAME:-}"
      if [ -n "$C" ]; then
        warn "官方源不可用（EOL 系统），切换 archive.debian.org..."
        $SUDO cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true
        printf 'deb http://archive.debian.org/debian %s main contrib non-free\ndeb http://archive.debian.org/debian-security %s/updates main contrib non-free\n' "$C" "$C" | $SUDO tee /etc/apt/sources.list >/dev/null
        echo 'Acquire::Check-Valid-Until "false";' | $SUDO tee /etc/apt/apt.conf.d/99archive >/dev/null
        $SUDO apt-get update -qq >/dev/null 2>&1 || true
        $SUDO apt-get install -y -qq curl ca-certificates >/dev/null 2>&1 || true
      fi
    fi
  elif command -v yum >/dev/null 2>&1; then
    $SUDO yum install -y -q curl >/dev/null 2>&1 || true
  elif command -v apk >/dev/null 2>&1; then
    $SUDO apk add --no-cache curl >/dev/null 2>&1 || true
  fi
  command -v curl >/dev/null 2>&1 || die "curl 安装失败，请手动安装 curl 后重试"
}

install_docker() {
  warn "未检测到 Docker，正在自动安装（约 1-3 分钟）..."

  # 1) 优先官方一键脚本
  if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh 2>/dev/null \
     && $SUDO sh /tmp/get-docker.sh >/tmp/docker-install.log 2>&1 \
     && command -v docker >/dev/null 2>&1; then
    log "Docker 安装完成（官方脚本）"
    return 0
  fi

  # 2) 官方脚本失败（Debian 10 等 EOL 系统会因个别包不存在而整体失败）→ 按源装核心包
  warn "官方脚本未成功（EOL 系统常见），改用官方源直接安装核心包..."
  . /etc/os-release 2>/dev/null || true
  DIST="${ID:-debian}"
  CODE="${VERSION_CODENAME:-}"
  [ "$DIST" = "ubuntu" ] || [ "$DIST" = "debian" ] || DIST="debian"

  if command -v apt-get >/dev/null 2>&1; then
    $SUDO install -m 0755 -d /etc/apt/keyrings
    if curl -fsSL "https://download.docker.com/linux/$DIST/gpg" \
        | $SUDO tee /etc/apt/keyrings/docker.asc >/dev/null 2>&1; then
      $SUDO chmod a+r /etc/apt/keyrings/docker.asc
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$DIST $CODE stable" \
        | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
      $SUDO apt-get update -qq >/dev/null 2>&1 || true
      $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1 || true
    fi
  elif command -v yum >/dev/null 2>&1; then
    $SUDO yum install -y -q yum-utils >/dev/null 2>&1 || true
    $SUDO yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1 || true
    $SUDO yum install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1 || true
  fi

  command -v docker >/dev/null 2>&1 || die "Docker 安装失败，请手动安装后重试"
  return 0
}

ensure_curl
command -v docker >/dev/null 2>&1 || install_docker

# 启动并设置开机自启
$SUDO systemctl enable --now docker >/dev/null 2>&1 \
  || $SUDO service docker start >/dev/null 2>&1 \
  || true

if $SUDO docker compose version >/dev/null 2>&1; then
  DC="$SUDO docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="$SUDO docker-compose"
else
  warn "缺少 compose 插件，正在安装..."
  $SUDO apt-get update -qq >/dev/null 2>&1 || true
  $SUDO apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1 || true
  $SUDO yum install -y docker-compose-plugin >/dev/null 2>&1 || true
  if ! $SUDO docker compose version >/dev/null 2>&1; then
    # 兜底：下载 compose v2 静态二进制作为 CLI 插件
    case "$(uname -m)" in aarch64|arm64) ARCH=aarch64 ;; *) ARCH=x86_64 ;; esac
    $SUDO mkdir -p /usr/libexec/docker/cli-plugins
    if curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$ARCH" -o /tmp/docker-compose 2>/dev/null; then
      $SUDO install -m 0755 /tmp/docker-compose /usr/libexec/docker/cli-plugins/docker-compose
      $SUDO ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose 2>/dev/null || true
    fi
  fi
  if $SUDO docker compose version >/dev/null 2>&1; then
    DC="$SUDO docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    DC="$SUDO docker-compose"
  else
    die "docker compose 安装失败，请手动安装 docker-compose-plugin 后重试"
  fi
fi
log "Docker 就绪：$(docker --version 2>/dev/null | head -1)"

# ---------- 3. 准备安装目录 ----------
$SUDO mkdir -p "$APP_DIR"

if [ -f "$SCRIPT_DIR/yuxiaxie-server/app.js" ]; then
  log "检测到本地源码，直接使用"
  $SUDO cp -a "$SCRIPT_DIR/yuxiaxie-server/." "$APP_DIR/"
elif [ -f "$SCRIPT_DIR/$PKG_NAME" ]; then
  log "发现本地安装包 $SCRIPT_DIR/$PKG_NAME，解压中..."
  $SUDO tar -xzf "$SCRIPT_DIR/$PKG_NAME" -C "$APP_DIR" --strip-components=1
else
  TMP="$(mktemp -d)"
  PKG_FILE="$TMP/$PKG_NAME"

  try_direct() {
    [ -n "$PKG_URL" ] || return 1
    log "下载安装包：$PKG_URL"
    curl -fL --max-time 600 "$PKG_URL" -o "$PKG_FILE" || return 1
    tar -tzf "$PKG_FILE" >/dev/null 2>&1
  }

  try_parts() {
    [ -n "$PKG_PARTS" ] || return 1
    log "下载安装包（分片）：$PKG_PARTS.part0 ..."
    : > "$TMP/pkg.b64"
    for i in 0 1 2 3 4 5 6 7; do
      if curl -fL --max-time 600 "$PKG_PARTS.part$i" -o "$TMP/part$i" 2>/dev/null \
         || curl -fL --max-time 600 "$PKG_PARTS2.part$i" -o "$TMP/part$i" 2>/dev/null; then
        cat "$TMP/part$i" >> "$TMP/pkg.b64"
      else
        break
      fi
    done
    [ -s "$TMP/pkg.b64" ] || return 1
    base64 -d "$TMP/pkg.b64" > "$PKG_FILE" 2>/dev/null || return 1
    tar -tzf "$PKG_FILE" >/dev/null 2>&1
  }

  if ! try_direct && ! try_parts; then
    die "安装包下载失败，请检查网络，或手动下载 $PKG_NAME 放到本脚本同目录后重试"
  fi
  log "校验并解压安装包..."
  $SUDO tar -xzf "$PKG_FILE" -C "$APP_DIR" --strip-components=1
  rm -rf "$TMP"
fi

cd "$APP_DIR"
[ -f app.js ] || die "安装目录内容异常，请检查安装包"
log "代码就位：$APP_DIR"

# ---------- 4. 生成 .env ----------
if [ ! -f .env ]; then
  log "生成 .env（随机密钥）"
  PUB_IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null \
            || curl -fsS --max-time 5 https://ipv4.icanhazip.com 2>/dev/null \
            || echo 127.0.0.1)"
  PUB_IP="$(echo "$PUB_IP" | tr -d '[:space:]')"
  ADMIN_PW="$(rand | cut -c1-12)"

  sed -e "s|^PUBLIC_HOST=.*|PUBLIC_HOST=${PUB_IP}|" \
      -e "s|^DB_ROOT_PASS=.*|DB_ROOT_PASS=$(rand)|" \
      -e "s|^DB_PASS=.*|DB_PASS=$(rand)|" \
      -e "s|^TOKEN_SECRET=.*|TOKEN_SECRET=$(rand)$(rand)|" \
      -e "s|^ADMIN_PASS=.*|ADMIN_PASS=${ADMIN_PW}|" \
      .env.docker.example > .env
  $SUDO chmod 600 .env
  log "管理员账号 admin / ${ADMIN_PW}  （已写入 $APP_DIR/.env）"
else
  warn ".env 已存在，沿用现有配置"
fi

set -a; . ./.env; set +a

# ---------- 5. 启动 ----------
log "拉取镜像并构建（首次约 2-5 分钟）..."
$SUDO env $(grep -v '^#' .env | grep -v '^$' | xargs) docker compose up -d --build

# ---------- 6. 等待健康 ----------
log "等待服务就绪..."
for i in $(seq 1 60); do
  if curl -fsS --max-time 2 "http://127.0.0.1:${HTTP_PORT:-3000}/health" >/dev/null 2>&1; then
    echo
    log "部署完成！"
    echo "----------------------------------------------------"
    echo "  游戏页面   : http://${PUBLIC_HOST}:${HTTP_PORT:-3000}/"
    echo "  后台管理   : http://${PUBLIC_HOST}:${HTTP_PORT:-3000}/admin/login"
    echo "  后台账号   : ${ADMIN_USER} / (见 $APP_DIR/.env 的 ADMIN_PASS)"
    echo "  WebSocket  : ws://${PUBLIC_HOST}:${WS_PORT_HOST:-18282}/ws"
    echo "  安装目录   : $APP_DIR"
    echo "----------------------------------------------------"
    echo "  常用命令：cd $APP_DIR && docker compose logs -f app   # 看日志"
    echo "            cd $APP_DIR && docker compose restart app   # 重启"
    echo "            cd $APP_DIR && docker compose down          # 停止"
    echo "----------------------------------------------------"
    echo "  注意：云服务器安全组需放行 TCP ${HTTP_PORT:-3000} 和 ${WS_PORT_HOST:-18282}"
    exit 0
  fi
  printf '.'
  sleep 3
done

echo
warn "服务尚未通过健康检查，请查看日志定位："
echo "  cd $APP_DIR && docker compose logs --tail=80 app"
exit 1
