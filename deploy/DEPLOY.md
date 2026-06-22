# 晶肤AI美肤助手 — 部署指南

## 概述

把项目从你的 Windows 电脑部署到阿里云服务器 (8.154.35.206)，让其他人通过 IP 地址使用。

---

## 第一步：在服务器上安装 Docker

SSH 登录到你的服务器，粘贴以下命令：

```bash
# 安装 Docker
curl -fsSL https://get.docker.com | bash

# 允许非 root 用户使用 docker
usermod -aG docker root

# 退出重新登录
exit
# 然后重新 SSH 进来

# 验证安装
docker --version
# 应显示: Docker version 28.x.x
```

---

## 第二步：上传项目代码到服务器

在**你本地电脑**的 PowerShell 或终端中执行：

```bash
# 先装一下依赖（确保 .env 存在）
cd D:\medical-aesthetics-ai-agent

# 创建后端 .env（用你的真实 KEY 替换）
echo DASHSCOPE_API_KEY=sk-你的真实KEY > backend\.env
echo ARK_API_KEY=你的真实KEY >> backend\.env
echo CHROMA_DB_PATH=/data/chroma_db >> backend\.env
echo CORS_ALLOWED_ORIGINS=* >> backend\.env

# 上传整个项目到服务器
scp -r . root@8.154.35.206:/opt/jfur/
```

> 如果你用不了 scp，也可以用 FTP 工具（如 FileZilla）传过去。

---

## 第三步：启动服务

SSH 回到服务器，执行：

```bash
cd /opt/jfur

# 构建镜像并启动（第一次会比较慢，要下载依赖）
docker compose -f deploy/docker-compose.yml up -d --build

# 查看启动日志，等看到 "服务启动完成"
docker compose -f deploy/docker-compose.yml logs -f

# 看到 ✅ 服务启动完成后，按 Ctrl+C 退出日志
```

---

## 第四步：验证

打开浏览器访问：**http://8.154.35.206**

应该能看到晶肤AI美肤助手的前端页面了！上传一张照片试试。

---

## 常用命令

```bash
cd /opt/jfur

# 查看所有服务状态
docker compose -f deploy/docker-compose.yml ps

# 重新构建和启动
docker compose -f deploy/docker-compose.yml up -d --build

# 重启
docker compose -f deploy/docker-compose.yml restart

# 停止
docker compose -f deploy/docker-compose.yml down

# 查看后端日志
docker compose -f deploy/docker-compose.yml logs -f backend

# 查看前端日志
docker compose -f deploy/docker-compose.yml logs -f frontend
```
