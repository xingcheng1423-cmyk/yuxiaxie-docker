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
if ! command -v docker >/dev/null 2>&1; then
  warn "未检测到 Docker，正在自动安装（约 1-3 分钟）..."
  curl -fsSL https://get.docker.com | $SUDO sh || die "Docker 安装失败，请手动安装后重试"
  $SUDO systemctl enable --now docker >/dev/null 2>&1 || true
fi

if $SUDO docker compose version >/dev/null 2>&1; then
  DC="$SUDO docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="$SUDO docker-compose"
else
  warn "缺少 compose 插件，正在安装..."
  $SUDO apt-get update -qq >/dev/null 2>&1 || true
  $SUDO apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1 \
    || $SUDO yum install -y docker-compose-plugin >/dev/null 2>&1 \
    || die "docker compose 安装失败"
  DC="$SUDO docker compose"
fi
log "Docker 就绪：$(docker --version)"

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
