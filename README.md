# 鱼虾蟹 H5 游戏 · Docker 一键部署

MySQL 8 + Redis 7 + Node.js 18 全套编排，一条命令装好，不用手动装 Node、建库、配 PM2。

## 一键部署

服务器上执行（root）：

```bash
curl -fsSL https://raw.githubusercontent.com/xingcheng1423-cmyk/yuxiaxie-docker/main/install.sh | bash
```

国内服务器走 jsDelivr CDN 更快：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/xingcheng1423-cmyk/yuxiaxie-docker@main/install.sh | bash
```

脚本自动完成：

1. 缺 `curl` 自动装（Debian 10 等 EOL 系统自动切 `archive.debian.org` 源）
2. 没 Docker 自动装（官方脚本失败时回退按源装 `docker-ce`/`containerd.io`/`docker-compose-plugin`）
3. 下载安装包（raw 不通自动换 jsDelivr 镜像）
4. 生成 `.env`：随机数据库密码、随机 `TOKEN_SECRET`、随机后台密码
5. `docker compose up -d --build` 起 MySQL + Redis + 游戏服
6. 健康检查通过后打印访问地址

重跑同一条命令即可升级代码，**数据库数据在 docker volume 里，不会丢**。

## 部署完的地址

| 用途 | 地址 |
|---|---|
| 游戏页面 | `http://服务器IP:3000/` |
| 后台管理 | `http://服务器IP:3000/admin/login` |
| WebSocket | `ws://服务器IP:18282/ws` |

后台密码在服务器 `/opt/yuxiaxie/.env` 的 `ADMIN_PASS`。
**记得在云服务器安全组放行 TCP 3000 和 18282。**

## 仓库内容

| 文件 | 说明 |
|---|---|
| `install.sh` | 一键部署脚本（也是服务器上唯一需要下载的文件，安装包由它自己拉） |
| `yuxiaxie-docker.tar.gz` | 完整安装包（源码 + Dockerfile + docker-compose.yml + 部署文档） |
| `SHA256SUMS.txt` | 校验值 |

手动下载安装包部署：

```bash
mkdir -p /opt/yuxiaxie && cd /opt/yuxiaxie
curl -fL -o pkg.tar.gz https://raw.githubusercontent.com/xingcheng1423-cmyk/yuxiaxie-docker/main/yuxiaxie-docker.tar.gz
tar -xzf pkg.tar.gz --strip-components=1
cp .env.docker.example .env && vi .env    # 改 PUBLIC_HOST 和各项密码
docker compose up -d --build
```

## 常用运维

```bash
cd /opt/yuxiaxie
docker compose ps            # 状态
docker compose logs -f app   # 日志
docker compose restart app   # 重启
docker compose down          # 停止（保留数据）
docker compose down -v       # 清库重来（危险，数据全丢）
docker exec -it yxx-mysql mysql -ubaye -p baye   # 进数据库

# 备份数据库
docker exec yxx-mysql mysqldump -uroot -p"$DB_ROOT_PASS" baye | gzip > backup_$(date +%F).sql.gz
```

## 常见问题

**构建慢 / apk 卡住**
Dockerfile 默认用阿里云 apk 源 + npmmirror npm 源。海外机器可覆盖：
```bash
docker compose build --build-arg APK_MIRROR=dl-cdn.alpinelinux.org --build-arg NPM_REGISTRY=https://registry.npmjs.org
```

**外网打不开**
先在服务器上 `curl http://127.0.0.1:3000/health` 确认服务本身正常，再检查安全组是否放行 3000 和 18282。

**改了 DB 密码不生效**
MySQL 只在数据卷首次初始化时读环境变量，需 `docker compose down -v` 清库重来（会丢数据）。

**要换端口**
只改 `HTTP_PORT` 可以；`WS_PORT_HOST` 必须同步改 `public/game.js` 里的 `wsPort`，否则客户端连不上。
