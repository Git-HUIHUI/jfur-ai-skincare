# 项目修改记录 (CHANGELOG)

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
