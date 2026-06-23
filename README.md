# 晶肤AI美肤助手 — Demo

为晶肤医美（朗姿股份旗下轻医美连锁品牌）开发的AI智能体Demo，用于面试展示。

## 技术栈

| 层级 | 技术 |
|------|------|
| 前端 | Next.js 14 + Vercel AI SDK + Tailwind CSS + shadcn/ui |
| 后端 | Python FastAPI + SSE 流式响应 |
| 智能体 | LangGraph（5节点 + 条件路由 + SQLite 持久化） |
| 聊天模型 | Qwen-VL-Max（多模态，图片+文字）/ Qwen-Max（纯文字） |
| 图生图 | 火山方舟 Seedream 4.5（图生图，基于用户照片做效果模拟） |
| RAG | ChromaDB + BAAI/bge-small-zh-v1.5 |
| 会话持久化 | AsyncSqliteSaver（checkpoint 存 SQLite，重启不丢） |

## 模型分工

| 用途 | 模型 | 说明 |
|------|------|------|
| 皮肤分析（有图） | `qwen-vl-max` | 多模态视觉理解，分析面部照片 |
| 皮肤分析（无图） | `qwen-max` | 纯文字模型，降级处理 |
| 追问确认 | `qwen-max` | 判断用户意图 + 生成追问问题 |
| 方案匹配 | ChromaDB 向量检索 | 本地 RAG，不调 LLM |
| 效果图生成 | `doubao-seedream-4-5-251128` | 火山方舟图生图，传入用户照片做参考 |
| Embedding | `BAAI/bge-small-zh-v1.5` | 向量化知识库文档 |

> **关键改进**（2026-06-20）：效果预览从 `wanx-v1`（文生图，与用户照片无关）升级为 `Seedream 4.5`（图生图），通过 `image` 参数传入用户上传的照片，实现基于本人面部特征的医美效果模拟。

## 项目结构

```
medical-aesthetics-ai-agent/
├── backend/
│   ├── agent/
│   │   ├── graph.py              # LangGraph 状态图编排 + SQLite 持久化
│   │   └── nodes/
│   │       ├── analyze.py        # 节点1: 皮肤分析（Qwen-VL-Max / Qwen-Max）
│   │       ├── ask_followup.py   # 节点2: 追问确认（Qwen-Max）
│   │       ├── match_product.py  # 节点3: RAG 方案匹配（ChromaDB）
│   │       ├── generate_preview.py # 节点4: 图生图效果预览（Seedream 4.5）
│   │       └── book_appointment.py # 节点5: 预约引导（Mock 门店）
│   ├── rag/
│   │   └── chroma_store.py       # ChromaDB 向量检索（5个项目）
│   ├── knowledge/
│   │   └── projects.py           # 光子嫩肤/果酸焕肤/水光针/超皮秒/除皱瘦脸针
│   ├── utils/
│   │   └── retry.py              # API 重试工具
│   ├── chroma_db/
│   │   ├── chroma.sqlite3        # 向量数据库
│   │   └── checkpoints.db        # LangGraph 会话持久化
│   ├── uploads/                  # 用户上传的图片
│   ├── main.py                   # FastAPI + SSE 流式（走 app_graph.astream()）
│   ├── config.py                 # 环境变量 + 模型配置
│   ├── requirements.txt
│   ├── .env.example              # 环境变量示例
│   └── .env                      # DASHSCOPE_API_KEY, ARK_API_KEY
├── frontend/
│   ├── app/
│   │   ├── page.tsx              # 聊天主页面（精简后 ~230 行）
│   │   ├── layout.tsx            # 根布局
│   │   ├── globals.css           # 全局样式
│   │   └── api/chat/route.ts     # Next.js API 代理 → 后端
│   ├── components/
│   │   ├── chat/                 # 聊天组件
│   │   └── ErrorBoundary.tsx     # 错误边界组件
│   ├── lib/types.ts              # 共享类型定义
│   ├── .env.example              # 环境变量示例
│   ├── package.json
│   └── tailwind.config.ts
└── README.md
```

## 快速启动

### 环境要求

- Python 3.10+
- Node.js 18+
- 阿里云百炼 DashScope API Key（用于 Qwen 模型）
- 火山方舟 ARK API Key（用于 Seedream 图生图）

### 1. 后端

```bash
cd backend

# 安装依赖
pip install -r requirements.txt

# 配置环境变量
cp .env.example .env
# 编辑 .env，填入 API Key

# 启动（默认 http://localhost:8001）
uvicorn main:app --host 0.0.0.0 --port 8001
```

### 2. 前端

```bash
cd frontend

# 安装依赖
npm install

# 配置环境变量
cp .env.example .env.local
# 编辑 .env.local：BACKEND_URL 供服务端代理使用，默认 http://localhost:8001 即可

# 启动（默认 http://localhost:3000）
npm run dev
```

### 3. ngrok 公网分享（可选）

详细操作见 [启动指南.md](./启动指南.md)。

```bash
python start_ngrok.py
```

## 功能流程

```
[条件路由: 有图? / 确认消息?]
        │
        ├─ 有图 → analyze → ask_followup
        └─ 确认文字 → ask_followup（跳过 analyze）
                            │
              ┌──未确认───┴── 已确认 ───────────┐
              │                                  │
              END (等用户回复)                    match_product
                                                 │（ChromaDB RAG）
                                          human_review
                                          （Demo 自动通过）
                                                 │
                                          generate_preview
                                          （Seedream 4.5 + 用户照片）
                                                 │
                                          book_appointment
                                          （门店 + 预约引导）
```

## 改进记录

详见 [docs/CHANGELOG.md](./docs/CHANGELOG.md)。

## API 端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/chat` | POST | 聊天接口，支持图片上传 |
| `/api/health` | GET | 健康检查 |

## 合规声明

- 所有AI分析标注"不是医学诊断"
- 所有推荐标注"以医生面诊为准"
- 所有效果图标注"模拟效果，因人而异"
