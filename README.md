# 鱼虾蟹 H5 游戏 · Docker 一键部署

MySQL 8 + Redis 7 + Node.js 全套编排，一条命令装好，不用装 Node、建库、配 PM2。

## 一键部署

服务器上执行（root）：

```bash
curl -fsSL https://raw.githubusercontent.com/xingcheng1423-cmyk/yuxiaxie-docker/main/install.sh | bash
```

国内服务器走 jsDelivr CDN 更快：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/xingcheng1423-cmyk/yuxiaxie-docker@main/install.sh | bash
```

脚本自动：装 Docker → 下载安装包 → 生成随机数据库/后台密码 → 起 MySQL+Redis+游戏服 → 健康检查通过后打印访问地址。

## 部署完的地址

| 用途 | 地址 |
|---|---|
| 游戏页面 | `http://服务器IP:3000/` |
| 后台管理 | `http://服务器IP:3000/admin/login` |
| WebSocket | `ws://服务器IP:18282/ws` |

后台密码在服务器 `/opt/yuxiaxie/.env` 的 `ADMIN_PASS`。

**记得在云服务器安全组放行 TCP 3000 和 18282。**

## 常见问题

**构建慢 / apk 卡住**
Dockerfile 默认用阿里云 apk 源 + npmmirror npm 源。海外机器可覆盖：
```bash
docker compose build --build-arg APK_MIRROR=dl-cdn.alpinelinux.org --build-arg NPM_REGISTRY=https://registry.npmjs.org
```

**外网打不开**
先 `curl http://127.0.0.1:3000/health` 确认服务本身正常，再检查安全组放行 3000 和 18282。

**改了 DB 密码不生效**
MySQL 只在数据卷首次初始化时读环境变量，需 `docker compose down -v` 清库重来（会丢数据）。
