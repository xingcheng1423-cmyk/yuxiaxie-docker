#!/usr/bin/env bash
# ============================================================
#  鱼虾蟹 H5 游戏 - 一键卸载
#  用法：
#    curl -fsSL <URL>/uninstall.sh | bash                  # 交互确认（连数据库一起删）
#    curl -fsSL <URL>/uninstall.sh | bash -s -- --yes      # 不询问，直接删
#    curl -fsSL <URL>/uninstall.sh | bash -s -- --keep-data   # 保留数据库数据（只停服务）
#    curl -fsSL <URL>/uninstall.sh | bash -s -- --purge-docker # 连 Docker 引擎一起卸
#  或本地：bash uninstall.sh [选项] [安装目录]
# ============================================================
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/yuxiaxie}"
KEEP_DATA=0
ASSUME_YES=0
PURGE_DOCKER=0

for a in "$@"; do
  case "$a" in
    --keep-data)    KEEP_DATA=1 ;;
    --yes|-y)       ASSUME_YES=1 ;;
    --purge-docker) PURGE_DOCKER=1 ;;
    /*)             APP_DIR="$a" ;;
    *)              ;;
  esac
done

log()  { printf '\033[32m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- root ----------
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
  command -v sudo >/dev/null 2>&1 || die "请用 root 运行：su - 后重新执行"
else
  SUDO=""
fi

echo "=============================================="
echo "  鱼虾蟹 一键卸载"
echo "  安装目录: $APP_DIR"
if [ "$KEEP_DATA" = "1" ]; then
  echo "  模式: 保留数据库数据（只停服务、删容器）"
else
  echo "  模式: 彻底删除（容器 + 数据库数据 + 镜像 + 目录）"
fi
echo "=============================================="

# ---------- 确认 ----------
if [ "$ASSUME_YES" != "1" ]; then
  if [ "$KEEP_DATA" = "1" ]; then
    printf '确认要停止服务吗？(输入 yes 继续): '
  else
    printf '\033[31m这会删除全部游戏数据（用户/余额/流水），不可恢复！\033[0m 输入 yes 继续: '
  fi
  read -r ans </dev/tty || ans=""
  [ "$ans" = "yes" ] || die "已取消"
fi

# ---------- 停止并删除容器 ----------
if command -v docker >/dev/null 2>&1; then
  if [ -f "$APP_DIR/docker-compose.yml" ]; then
    cd "$APP_DIR"
    if [ "$KEEP_DATA" = "1" ]; then
      log "停止并删除容器（保留数据卷）..."
      $SUDO docker compose down --remove-orphans 2>/dev/null || true
    else
      log "停止并删除容器 + 数据卷..."
      $SUDO docker compose down -v --remove-orphans 2>/dev/null || true
    fi
  else
    warn "找不到 $APP_DIR/docker-compose.yml，尝试直接清理同名容器..."
    for c in yxx-app yxx-mysql yxx-redis; do
      $SUDO docker rm -f "$c" >/dev/null 2>&1 || true
    done
    if [ "$KEEP_DATA" != "1" ]; then
      for v in yuxiaxie_mysql-data yuxiaxie_redis-data; do
        $SUDO docker volume rm "$v" >/dev/null 2>&1 || true
      done
    fi
    $SUDO docker network rm yuxiaxie_yxx >/dev/null 2>&1 || true
  fi

  # ---------- 删除应用镜像 ----------
  log "删除应用镜像 yuxiaxie-server:latest ..."
  $SUDO docker rmi -f yuxiaxie-server:latest >/dev/null 2>&1 || true

  # 顺手清理无主镜像（只删 dangling，不动其他项目的）
  $SUDO docker image prune -f >/dev/null 2>&1 || true
else
  warn "未检测到 docker，跳过容器清理"
fi

# ---------- 删除安装目录 ----------
if [ "$KEEP_DATA" = "1" ]; then
  warn "保留安装目录（含 .env 与数据卷），未删除：$APP_DIR"
else
  if [ -d "$APP_DIR" ]; then
    log "删除安装目录：$APP_DIR"
    $SUDO rm -rf "$APP_DIR"
  fi
fi

# ---------- 可选：卸载 Docker 引擎 ----------
if [ "$PURGE_DOCKER" = "1" ]; then
  warn "卸载 Docker 引擎（所有用这台机器的容器都会受影响）..."
  if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get remove -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin >/dev/null 2>&1 || true
    $SUDO apt-get autoremove -y -qq >/dev/null 2>&1 || true
  elif command -v yum >/dev/null 2>&1; then
    $SUDO yum remove -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1 || true
  fi
  $SUDO rm -rf /var/lib/docker /var/lib/containerd >/dev/null 2>&1 || true
  log "Docker 已卸载"
fi

echo "----------------------------------------------------"
if [ "$KEEP_DATA" = "1" ]; then
  log "已停止并删除容器，数据保留"
  echo "  重新部署：删掉 $APP_DIR/.env 后重跑安装命令即可（或直接 docker compose up -d）"
else
  log "卸载完成，已清理干净"
  echo "  如需连 Docker 一起卸载：bash uninstall.sh --purge-docker --yes"
fi
echo "----------------------------------------------------"
