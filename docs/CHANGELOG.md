# 项目修改记录 (CHANGELOG)

## 2026-06-23 - ngrok 公网访问修复

### 修复问题
- **公网访问后端连接失败** — 远程用户浏览器直连 `localhost:8001` 会连到自己的电脑，导致「无法连接到后端服务」
- 前端改为请求同源 `/api/chat`，由 Next.js 服务端代理转发到本机 FastAPI

### 文档更新
- `README.md` — 新增「公网分享与 API 代理」章节
- `启动指南.md` — 补充原理说明、环境变量、故障排查与自检命令
- `frontend/.env.example` — 改用 `BACKEND_URL`，注明勿用 `NEXT_PUBLIC_API_URL`

### 文件修改清单

| 文件路径 | 说明 |
|---------|-----|
| `frontend/app/page.tsx` | 浏览器统一走 `/api/chat` |
| `frontend/app/api/chat/route.ts` | 服务端代理读取 `BACKEND_URL` |
| `frontend/.env.example` | 环境变量说明更新 |
| `start_ngrok.py` | 增加公网分享提示 |

## 2026-06-21 - 优化和修复

### 新增功能
- **自动图片清理机制** - 每小时自动清理上传目录中超过24小时的文件
  - 添加 `backend/utils/cleanup.py`
  - 添加手动清理 API 端点 `POST /api/admin/cleanup`
- **CORS 配置改进** - 支持从环境变量配置允许的来源

### 修复问题
1. **ask_followup 误判问题** - 第一次调用时强制 `confirmed=False`，防止流程异常跳转
2. **FollowupCard 快速回复问题** - 不再把问题本身作为快速回复显示
3. **前端渲染错误** - 所有组件添加安全检查，防止循环引用 JSON 序列化错误
4. **上传图片后流程混乱** - 优化流程控制逻辑

### 代码优化
- **安全性增强** - 所有组件添加安全内容处理
- **错误处理改进** - 前端引入 ErrorBoundary
- **配置改进** - 支持 CORS 和其他配置项通过环境变量控制

### 文件修改清单

| 文件路径 | 说明 |
|---------|-----|
| `backend/utils/cleanup.py` | 新增 - 图片清理工具 |
| `backend/utils/__init__.py` | 新增 |
| `backend/agent/nodes/ask_followup.py` | 修复 - 添加强制 confirmed=False |
| `backend/config.py` | 更新 - 添加 CORS 和其他配置项 |
| `backend/main.py` | 更新 - 使用 CORS 配置 |
| `backend/.env.example` | 更新 - 添加配置说明 |
| `frontend/components/ErrorBoundary.tsx` | 新增 - 错误边界组件 |
| `frontend/components/chat/AnalysisCard.tsx` | 更新 - 安全内容处理 |
| `frontend/components/chat/FollowupCard.tsx` | 更新 - 快速回复修复 |
| `frontend/components/chat/UserBubble.tsx` | 更新 - 安全内容处理 |
| `frontend/app/page.tsx` | 更新 - 使用 ErrorBoundary，安全 getSafeString |
