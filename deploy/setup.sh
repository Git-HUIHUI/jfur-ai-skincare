#!/bin/bash
# ============================================================
# 晶肤AI美肤助手 — 一键部署脚本
# 功能：创建所有项目文件 + 安装 Docker + 构建启动
# 发给阿里云服务器智能助手执行即可
# ============================================================
set -e

PUBLIC_IP="8.154.35.206"
BASE="/opt/jfur"

echo "============================================"
echo " 晶肤AI美肤助手 — 一键部署"
echo " 目标服务器: ${PUBLIC_IP}"
echo "============================================"

# ============================================================
# 1. 安装 Docker
# ============================================================
echo ""
echo "[1/5] 检查并安装 Docker..."
if ! command -v docker &>/dev/null; then
    echo "正在安装 Docker..."
    curl -fsSL https://get.docker.com | bash
    echo "Docker 安装完成"
else
    echo "Docker 已安装: $(docker --version)"
fi

# ============================================================
# 2. 创建所有目录
# ============================================================
echo ""
echo "[2/5] 创建项目目录结构..."
mkdir -p "$BASE"/{backend/agent/nodes,backend/knowledge,backend/rag,backend/utils}
mkdir -p "$BASE"/{frontend/app/api/chat,frontend/components/chat,frontend/lib}
mkdir -p "$BASE"/deploy

# ============================================================
# 3. 创建所有项目文件
# ============================================================
echo ""
echo "[3/5] 创建项目文件..."

# ---------- 后端: requirements.txt ----------
cat > "$BASE/backend/requirements.txt" << 'EOF'
fastapi>=0.115.0
uvicorn[standard]>=0.30.0
python-dotenv>=1.0.1
langgraph>=0.2.0
langchain>=0.2.0
langchain-core>=0.2.0
langchain-openai>=0.2.0
chromadb>=0.5.0
sentence-transformers>=3.0.0
dashscope>=1.20.0
openai>=1.50.0
python-multipart>=0.0.9
pydantic>=2.9.0
EOF

# ---------- 后端: config.py ----------
cat > "$BASE/backend/config.py" << 'EOF'
import os
import sys
from dotenv import load_dotenv

load_dotenv()


def validate_env() -> bool:
    errors = []
    if not os.getenv("DASHSCOPE_API_KEY"):
        errors.append("DASHSCOPE_API_KEY 未配置（阿里云百炼 API Key）")
    if not errors:
        return True
    print("=" * 60)
    print("⚠️  环境变量配置问题：")
    for err in errors:
        print(f"  - {err}")
    print("\n请复制 backend/.env.example 为 backend/.env 并填入配置")
    print("=" * 60)
    return False


# ========== 核心配置 ==========
DASHSCOPE_API_KEY = os.getenv("DASHSCOPE_API_KEY", "")
CHROMA_DB_PATH = os.getenv("CHROMA_DB_PATH", "./chroma_db")
DASHSCOPE_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
QWEN_VL_MODEL = "qwen-vl-max"
QWEN_TEXT_MODEL = "qwen-max"
BGE_MODEL = "BAAI/bge-small-zh-v1.5"

# ========== 火山方舟 (Ark) — Seedream 4.5 图生图 ==========
ARK_API_KEY = os.getenv("ARK_API_KEY", "")
ARK_BASE_URL = "https://ark.cn-beijing.volces.com/api/v3"
ARK_IMAGE_MODEL = "doubao-seedream-4-5-251128"

# ========== 服务配置 ==========
UPLOADS_BASE_URL = os.getenv("UPLOADS_BASE_URL", "http://localhost:8001")

# ========== 图片上传限制 ==========
MAX_IMAGE_SIZE_MB = 10
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp"}

# ========== API 配置 ==========
API_RETRY_TIMES = 2
API_RETRY_DELAY = 1.0

# ========== CORS 配置 ==========
CORS_ALLOWED_ORIGINS = os.getenv("CORS_ALLOWED_ORIGINS", "*")
EOF

# ---------- 后端: main.py ----------
cat > "$BASE/backend/main.py" << 'EOF'
"""
FastAPI + SSE streaming chat API.
POST /api/chat — multipart/form-data with messages (JSON) + image (file)
Returns SSE stream of the agent's response.
"""

import json
import asyncio
import uuid
import os
import logging
from pathlib import Path
from typing import List, Optional
from contextlib import asynccontextmanager
from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from rag.chroma_store import init_knowledge_base
from agent.graph import get_agent
from utils.cleanup import cleanup_old_files, periodic_cleanup_task
from config import (
    validate_env,
    MAX_IMAGE_SIZE_MB,
    ALLOWED_IMAGE_TYPES,
    CORS_ALLOWED_ORIGINS,
)

# ========== 日志配置 ==========
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

_cleanup_task = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _cleanup_task

    logger.info("=" * 60)
    logger.info("🚀 晶肤AI美肤助手启动中...")
    logger.info("=" * 60)

    if not validate_env():
        logger.warning("环境变量未完全配置，部分功能可能不可用")
    else:
        logger.info("✅ 环境变量验证通过")

    try:
        count = init_knowledge_base()
        logger.info(f"✅ ChromaDB 初始化完成，共 {count} 个项目")
    except Exception as e:
        logger.exception("ChromaDB 初始化失败")

    _cleanup_task = asyncio.create_task(
        periodic_cleanup_task(UPLOADS_DIR, hours=24, interval_seconds=3600)
    )
    logger.info("✅ 定时清理任务已启动")

    logger.info("=" * 60)
    logger.info("✅ 服务启动完成")
    logger.info("=" * 60)

    yield

    if _cleanup_task:
        _cleanup_task.cancel()
        try:
            await _cleanup_task
        except asyncio.CancelledError:
            pass
        logger.info("✅ 定时清理任务已停止")


app = FastAPI(
    title="晶肤AI美肤助手 API",
    version="0.1.0",
    lifespan=lifespan
)


def get_cors_origins():
    if CORS_ALLOWED_ORIGINS == "*":
        return ["*"]
    return [o.strip() for o in CORS_ALLOWED_ORIGINS.split(",") if o.strip()]


app.add_middleware(
    CORSMiddleware,
    allow_origins=get_cors_origins(),
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOADS_DIR = Path(__file__).parent / "uploads"
UPLOADS_DIR.mkdir(exist_ok=True)
app.mount("/uploads", StaticFiles(directory=str(UPLOADS_DIR)), name="uploads")


class ChatRequest(BaseModel):
    messages: List[dict]
    image_base64: Optional[str] = None
    thread_id: Optional[str] = None


# ===== SSE Helpers =====
def sse_event(event: str, data: dict) -> str:
    payload = json.dumps(data, ensure_ascii=False)
    return f"event: {event}\ndata: {payload}\n\n"


async def sse_stream(events):
    async for evt in events:
        yield sse_event(evt["event"], evt["data"])


async def run_agent_events(image_base64, image_url, user_text, conversation_state=None):
    app_graph = await get_agent()
    conv_state = conversation_state or {}
    thread_id = conv_state.get("thread_id", str(uuid.uuid4()))

    is_resuming = bool(thread_id and conversation_state and not image_base64)

    if is_resuming:
        initial_state = {
            "user_text": user_text or "",
            "last_user_reply": user_text or "",
            "messages": [
                {"role": "user", "type": "text", "content": user_text or ""}
            ],
        }
    else:
        initial_state = {
            "user_text": user_text or "",
            "last_user_reply": user_text or "",
            "messages": conv_state.get("messages", []),
            "analysis_result": "",
            "followup_message": "",
            "followup_confirmed": False,
            "recommendations": [],
            "recommendation_message": "",
            "preview_image_urls": [],
            "preview_message": "",
            "booking_message": "",
            "stores": [],
            "current_step": "",
            "needs_followup": False,
            "approved": False,
        }
        if image_base64:
            initial_state["image_base64"] = image_base64
            initial_state["image_url"] = image_url

    config = {"configurable": {"thread_id": thread_id}}

    step_labels = {
        "analyze": "🔍 正在分析您的皮肤表面特征...",
        "ask_followup": "💬 正在进行追问确认...",
        "match_product": "📋 正在匹配适合您的项目方案...",
        "human_review": "✅ 方案审核通过...",
        "generate_preview": "🎨 正在生成效果模拟图...",
        "book_appointment": "🏥 正在准备预约引导...",
    }

    try:
        yield {
            "event": "status",
            "data": {
                "type": "status",
                "content": "🔍 开始分析您的皮肤状况...",
                "step": "start"
            }
        }

        previous_step = None
        final_state = None
        already_done = False

        async for chunk in app_graph.astream(initial_state, config):
            node_name = list(chunk.keys())[0] if isinstance(chunk, dict) and chunk else None
            node_state = chunk.get(node_name, {}) if node_name else {}

            if node_name is None:
                continue

            current_step = node_state.get("current_step", node_name)
            messages = node_state.get("messages", [])

            if current_step != previous_step:
                label = step_labels.get(current_step, f"⏳ {current_step}")
                yield {
                    "event": "status",
                    "data": {"type": "status", "content": label, "step": current_step}
                }

            if current_step == "analyze":
                yield {
                    "event": "analysis",
                    "data": {
                        "type": "analysis",
                        "content": node_state.get("analysis_result", ""),
                        "step": "analyze",
                        "disclaimer": "⚠️ 以上为AI皮肤表面特征描述，不是医学诊断，具体以医生面诊为准。"
                    }
                }

            elif current_step == "ask_followup":
                if node_state.get("followup_confirmed"):
                    pass
                else:
                    yield {
                        "event": "followup",
                        "data": {
                            "type": "followup",
                            "content": node_state.get("followup_message", ""),
                            "step": "ask_followup",
                            "thread_id": thread_id,
                            "analysis_result": node_state.get("analysis_result", "")
                        }
                    }
                    yield {
                        "event": "done",
                        "data": {"type": "done", "step": "ask_followup", "thread_id": thread_id}
                    }
                    already_done = True

            elif current_step == "match_product":
                recs = node_state.get("recommendations", [])
                yield {
                    "event": "recommendation",
                    "data": {
                        "type": "recommendation",
                        "content": node_state.get("recommendation_message", ""),
                        "recommendations": recs,
                        "step": "match_product"
                    }
                }

            elif current_step == "human_review":
                review_msg = ""
                for m in messages:
                    if m.get("type") == "text":
                        review_msg = m.get("content", "")
                yield {
                    "event": "review",
                    "data": {
                        "type": "text",
                        "content": review_msg or "✅ [审核检查点] 方案已自动通过（Demo模式）",
                        "step": "human_review"
                    }
                }

            elif current_step == "generate_preview":
                preview_urls = node_state.get("preview_image_urls", [])
                if preview_urls:
                    yield {
                        "event": "preview",
                        "data": {
                            "type": "preview",
                            "content": "效果模拟图已生成",
                            "image_urls": preview_urls,
                            "disclaimer": "⚠️ 以上为模拟效果，实际效果因人而异，以医生面诊为准",
                            "step": "generate_preview"
                        }
                    }
                else:
                    yield {
                        "event": "text",
                        "data": {
                            "type": "text",
                            "content": f"⚠️ {node_state.get('preview_message', '效果图生成失败')}",
                            "step": "generate_preview"
                        }
                    }

            elif current_step == "book_appointment":
                booking_msg = node_state.get("booking_message", "")
                stores = node_state.get("stores", [])
                yield {
                    "event": "booking",
                    "data": {
                        "type": "booking",
                        "content": booking_msg,
                        "stores": stores,
                        "step": "book_appointment"
                    }
                }

            previous_step = current_step
            final_state = node_state

        if not already_done:
            yield {
                "event": "done",
                "data": {
                    "type": "done",
                    "step": final_state.get("current_step", "completed") if final_state else "completed",
                    "thread_id": thread_id
                }
            }

    except Exception as e:
        logger.exception("Agent execution error")
        yield {
            "event": "error",
            "data": {"type": "error", "content": f"处理出错：{str(e)}"}
        }


# ========== 图片验证辅助函数 ==========
async def validate_image(image: UploadFile) -> bytes:
    if not image:
        return b""

    content_type = image.content_type or ""
    if content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"不支持的图片类型。支持类型：{', '.join(ALLOWED_IMAGE_TYPES)}"
        )

    image_bytes = await image.read()
    size_mb = len(image_bytes) / (1024 * 1024)

    if size_mb > MAX_IMAGE_SIZE_MB:
        raise HTTPException(
            status_code=413,
            detail=f"图片大小超过限制（最大 {MAX_IMAGE_SIZE_MB}MB）"
        )

    logger.info(f"图片验证通过: {content_type}, {size_mb:.2f}MB")
    return image_bytes


# ========== API Endpoints ==========
@app.post("/api/chat")
async def chat(
    messages: str = Form(...),
    image: UploadFile = File(None),
    thread_id: str = Form(None)
):
    try:
        messages_list = json.loads(messages)
    except json.JSONDecodeError:
        return StreamingResponse(
            sse_stream([{"event": "error", "data": {"type": "error", "content": "messages 格式错误"}}]),
            media_type="text/event-stream"
        )

    user_text = ""
    for msg in reversed(messages_list):
        if isinstance(msg, dict) and msg.get("role") == "user":
            user_text = msg.get("content", "")
            if isinstance(user_text, list):
                text_parts = [p.get("text", "") for p in user_text if isinstance(p, dict) and p.get("type") == "text"]
                user_text = " ".join(text_parts)
            break

    image_base64 = None
    image_url = ""
    image_bytes = b""
    try:
        if image and image.filename:
            image_bytes = await validate_image(image)
            import base64
            image_base64 = base64.b64encode(image_bytes).decode("utf-8")

            fmt = Path(image.filename).suffix.lstrip(".").lower() or "jpg"
            if fmt == "jpg":
                fmt = "jpeg"
            image_url = f"data:image/{fmt};base64,{image_base64}"

            saved_name = f"{uuid.uuid4()}.{fmt}"
            (UPLOADS_DIR / saved_name).write_bytes(image_bytes)
    except HTTPException as e:
        return StreamingResponse(
            sse_stream([{"event": "error", "data": {"type": "error", "content": e.detail}}]),
            media_type="text/event-stream"
        )

    conv_state = {"thread_id": thread_id} if thread_id else {}

    return StreamingResponse(
        sse_stream(run_agent_events(image_base64, image_url, user_text, conv_state)),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@app.post("/api/chat/continue")
async def chat_continue(request: ChatRequest):
    user_text = ""
    for msg in reversed(request.messages):
        if isinstance(msg, dict) and msg.get("role") == "user":
            user_text = msg.get("content", "")
            break

    thread_id = request.thread_id
    conv_state = {"thread_id": thread_id} if thread_id else {}

    return StreamingResponse(
        sse_stream(run_agent_events(None, "", user_text, conv_state)),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@app.get("/api/health")
async def health():
    checks = {
        "status": "ok",
        "service": "晶肤AI美肤助手",
        "checks": {}
    }

    try:
        from config import DASHSCOPE_API_KEY
        checks["checks"]["env"] = "ok" if DASHSCOPE_API_KEY else "missing"
    except Exception:
        checks["checks"]["env"] = "error"

    try:
        from rag.chroma_store import get_chroma_collection
        col = get_chroma_collection()
        checks["checks"]["chromadb"] = "ok"
    except Exception:
        checks["checks"]["chromadb"] = "error"

    return checks


@app.post("/api/admin/cleanup")
async def manual_cleanup(hours: int = 24, dry_run: bool = False):
    result = cleanup_old_files(UPLOADS_DIR, hours, dry_run)
    return {
        "status": "ok",
        "message": "清理完成" if not dry_run else "试运行完成",
        "result": result
    }
EOF

# ---------- 后端: agent/graph.py ----------
cat > "$BASE/backend/agent/graph.py" << 'EOF'
"""
LangGraph State Graph — orchestrates the 5-node AI agent workflow.
Flow: analyze → ask_followup (loop until confirmed) → match_product → human_review → generate_preview → book_appointment
"""

import os
from typing import TypedDict, Annotated, Sequence, Optional
from langgraph.graph import StateGraph, END, START
from langgraph.checkpoint.sqlite.aio import AsyncSqliteSaver
from agent.nodes.analyze import analyze_skin
from agent.nodes.ask_followup import ask_followup
from agent.nodes.match_product import match_product
from agent.nodes.generate_preview import generate_preview
from agent.nodes.book_appointment import book_appointment


# ===== State Definition =====
class AgentState(TypedDict):
    image_base64: str
    image_url: str
    user_text: str
    messages: Annotated[Sequence[dict], lambda x, y: list(x) + list(y) if y else x]
    last_user_reply: str
    analysis_result: str
    followup_message: str
    followup_confirmed: bool
    recommendations: list
    recommendation_message: str
    preview_image_urls: list
    preview_message: str
    booking_message: str
    stores: list
    current_step: str
    needs_followup: bool
    approved: bool


# ===== Node Functions =====
async def node_analyze(state: AgentState) -> AgentState:
    image_url = state.get("image_url", "")
    has_image = bool(state.get("image_base64"))
    result = await analyze_skin(state.get("image_base64", ""), state.get("user_text", ""))
    if result.get("error"):
        return {
            "analysis_result": result["content"],
            "image_url": image_url,
            "current_step": "analyze",
            "needs_followup": False,
            "messages": [
                {"role": "ai", "type": "analysis_error", "content": result["content"],
                 "error_type": result.get("error_type", "")}
            ]
        }
    return {
        "analysis_result": result["content"],
        "image_url": image_url,
        "current_step": "analyze",
        "needs_followup": has_image,
        "messages": [
            {"role": "ai", "type": "analysis", "content": result["content"]}
        ]
    }


async def node_ask_followup(state: AgentState) -> AgentState:
    user_reply = state.get("last_user_reply", "")
    analysis_result = state.get("analysis_result", "")
    image_url = state.get("image_url", "")
    result = await ask_followup(analysis_result, user_reply)

    followup_confirmed = result.get("confirmed", False)
    followup_message = result.get("message", "")

    if followup_confirmed:
        return {
            "followup_message": followup_message,
            "followup_confirmed": True,
            "needs_followup": False,
            "current_step": "ask_followup",
            "image_url": image_url,
            "messages": [
                {"role": "ai", "type": "text", "content": followup_message}
            ]
        }
    else:
        return {
            "followup_message": followup_message,
            "followup_confirmed": False,
            "needs_followup": True,
            "current_step": "ask_followup",
            "image_url": image_url,
            "messages": [
                {"role": "ai", "type": "text", "content": followup_message}
            ]
        }


async def node_match_product(state: AgentState) -> AgentState:
    query = f"{state.get('analysis_result', '')} {state.get('followup_message', '')}"
    image_url = state.get("image_url", "")
    result = await match_product(query)

    return {
        "recommendations": result["recommendations"],
        "recommendation_message": result["message"],
        "image_url": image_url,
        "current_step": "match_product",
        "messages": [
            {
                "role": "ai",
                "type": "recommendation",
                "content": result["message"],
                "recommendations": result["recommendations"]
            }
        ]
    }


async def node_human_review(state: AgentState) -> AgentState:
    image_url = state.get("image_url", "")
    return {
        "approved": True,
        "image_url": image_url,
        "current_step": "human_review",
        "messages": [
            {"role": "system", "type": "text", "content": "[审核检查点] 方案已自动通过（Demo模式）。实际部署需人工审核。"}
        ]
    }


async def node_generate_preview(state: AgentState) -> AgentState:
    recommendations = state.get("recommendations", [])

    if not recommendations:
        improvements = "淡化痘印、提亮肤色、缩小毛孔"
    else:
        improvements = "、".join([
            f"针对{r.get('suitable', '皮肤问题')}进行改善"
            for r in recommendations
        ])

    result = await generate_preview(
        improvements,
        image_url=state.get("image_url", ""),
    )

    if result["success"]:
        return {
            "preview_image_urls": result["image_urls"],
            "preview_message": result["message"],
            "current_step": "generate_preview",
            "messages": [
                {
                    "role": "ai",
                    "type": "preview",
                    "content": "效果模拟图已生成",
                    "image_urls": result["image_urls"],
                    "disclaimer": "以上为模拟效果，实际效果因人而异，以医生面诊为准"
                }
            ]
        }
    else:
        return {
            "preview_image_urls": [],
            "preview_message": result["message"],
            "current_step": "generate_preview",
            "messages": [
                {
                    "role": "ai",
                    "type": "text",
                    "content": f"⚠️ {result['message']}"
                }
            ]
        }


async def node_book_appointment(state: AgentState) -> AgentState:
    recommendations = state.get("recommendations", [])
    result = await book_appointment(recommendations)

    return {
        "booking_message": result["message"],
        "stores": result.get("stores", []),
        "current_step": "book_appointment",
        "messages": [
            {
                "role": "ai",
                "type": "booking",
                "content": result["message"],
                "stores": result.get("stores", [])
            }
        ]
    }


# ===== Routing Logic =====
def route_entry(state: AgentState) -> str:
    user_text = (state.get("user_text") or "").lower()
    has_image = bool(state.get("image_base64"))

    if state.get("analysis_result") and not state.get("followup_confirmed"):
        return "ask_followup"

    if has_image:
        return "analyze"

    confirm_words = [
        "确认", "好的", "推荐给我", "直接推荐", "给我推荐",
        "帮我推荐", "介绍项目", "推荐项目", "给我方案",
    ]
    if any(kw in user_text for kw in confirm_words):
        return "ask_followup"

    return "analyze"


def route_after_followup(state: AgentState) -> str:
    if state.get("followup_confirmed", False):
        return "match_product"
    return END


def route_after_analyze(state: AgentState) -> str:
    if state.get("needs_followup", False):
        return "ask_followup"
    return END


def should_skip_preview(state: AgentState) -> str:
    if state.get("approved", False):
        return "generate_preview"
    return "book_appointment"


# ===== Build the Graph =====
DB_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "chroma_db", "checkpoints.db")

_checkpointer: Optional[AsyncSqliteSaver] = None
_checkpointer_ctx = None


async def _get_async_checkpointer() -> AsyncSqliteSaver:
    global _checkpointer, _checkpointer_ctx
    if _checkpointer is None:
        _checkpointer_ctx = AsyncSqliteSaver.from_conn_string(DB_PATH)
        _checkpointer = await _checkpointer_ctx.__aenter__()
    return _checkpointer


async def build_graph():
    workflow = StateGraph(AgentState)

    workflow.add_node("analyze", node_analyze)
    workflow.add_node("ask_followup", node_ask_followup)
    workflow.add_node("match_product", node_match_product)
    workflow.add_node("human_review", node_human_review)
    workflow.add_node("generate_preview", node_generate_preview)
    workflow.add_node("book_appointment", node_book_appointment)

    workflow.add_conditional_edges(
        START,
        route_entry,
        {"analyze": "analyze", "ask_followup": "ask_followup"}
    )
    workflow.add_conditional_edges(
        "analyze",
        route_after_analyze,
        {"ask_followup": "ask_followup", END: END}
    )

    workflow.add_conditional_edges(
        "ask_followup",
        route_after_followup,
        {"match_product": "match_product", END: END}
    )

    workflow.add_edge("match_product", "human_review")
    workflow.add_edge("human_review", "generate_preview")
    workflow.add_edge("generate_preview", "book_appointment")
    workflow.add_edge("book_appointment", END)

    checkpointer = await _get_async_checkpointer()
    app = workflow.compile(checkpointer=checkpointer)
    return app


_agent_graph = None


async def get_agent():
    global _agent_graph
    if _agent_graph is None:
        _agent_graph = await build_graph()
    return _agent_graph
EOF

# ---------- 后端: agent/nodes/analyze.py ----------
cat > "$BASE/backend/agent/nodes/analyze.py" << 'EOF'
"""
Node 1 — Skin Analysis (analyze)
Input: user's uploaded face photo + text description
Output: surface-level skin feature description (NO medical diagnosis)
"""

import base64
import traceback
import logging
from openai import OpenAI, AsyncOpenAI
from config import DASHSCOPE_API_KEY, DASHSCOPE_BASE_URL, QWEN_VL_MODEL, QWEN_TEXT_MODEL
from utils import retry_async

logger = logging.getLogger(__name__)


SYSTEM_PROMPT = """你是晶肤医美的AI美肤助手，名字叫"小肤"。

你的能力：
- 根据用户上传的面部照片，描述皮肤的表面特征（毛孔粗细、痘印位置与颜色、肤色均匀度、光泽度等）
- 介绍晶肤医美的轻医美项目，解释治疗原理和适用人群
- 根据用户需求匹配合适的项目组合

你的禁区（绝对不能做）：
- 不能做出任何医学诊断（如"你这是黄褐斑/痤疮"）
- 不能承诺治疗效果
- 不能说"你不需要看医生"
- 不能编造项目名称或价格

你的回复风格：
- 温暖、像朋友一样聊天
- 把专业知识用大白话解释
- 每次提到效果时，加上"效果因人而异，具体以医生面诊为准"
- 在推荐项目后，引导用户预约线下医生面诊

重要合规要求：
所有分析结果仅作为初步参考，不能替代专业医生的面诊和皮肤检测。如果你被问到皮肤病症相关的问题，请提醒用户这需要专业医生来判断。
"""


async def _call_analyze_api(has_image: bool, user_content, model: str) -> str:
    client = AsyncOpenAI(
        api_key=DASHSCOPE_API_KEY,
        base_url=DASHSCOPE_BASE_URL,
        timeout=60.0,
    )

    response = await client.chat.completions.create(
        model=model,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_content}
        ],
        stream=False,
        temperature=0.7,
        max_tokens=1024
    )

    return response.choices[0].message.content


async def analyze_skin(image_base64: str, user_text: str) -> dict:
    try:
        has_image = bool(image_base64)

        if has_image:
            user_content = [
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"}
                },
                {
                    "type": "text",
                    "text": f"请分析我上传的面部照片，描述皮肤的表面特征。我补充的需求是：{user_text if user_text else '请全面分析我的皮肤表面状况'}"
                }
            ]
            model = QWEN_VL_MODEL
        else:
            user_content = (
                f"用户没有上传照片，只发来了以下文字描述：\n\n"
                f"\"{user_text}\"\n\n"
                f"请根据文字描述，直接给出皮肤分析和建议。"
                f"如果没有具体描述皮肤问题，请友好地提醒用户上传照片可以让你进行更准确的表面特征分析，"
                f"同时你也可以基于文字描述的皮肤困扰给一些初步的轻医美项目科普建议。"
            )
            model = QWEN_TEXT_MODEL

        logger.info(f"开始皮肤分析 (has_image={has_image})")
        content = await retry_async(_call_analyze_api, has_image, user_content, model)
        logger.info("皮肤分析完成")

        return {"error": False, "content": content}

    except Exception as e:
        error_type = type(e).__name__
        logger.exception("皮肤分析失败")

        error_messages = {
            "APITimeoutError": "皮肤分析服务响应超时，请稍后重试",
            "AuthenticationError": "API 认证失败，请联系管理员",
            "RateLimitError": "请求过于频繁，请稍等片刻再试",
            "APIError": f"皮肤分析 API 异常：{str(e)}",
        }
        user_msg = error_messages.get(error_type, f"皮肤分析暂时无法完成，请稍后重试")

        return {
            "error": True,
            "error_type": f"analyze/{error_type}",
            "content": user_msg,
        }
EOF

# ---------- 后端: agent/nodes/ask_followup.py ----------
cat > "$BASE/backend/agent/nodes/ask_followup.py" << 'EOF'
"""
Node 2 — Follow-up Questions (ask_followup)
Input: analysis result from node 1
Output: targeted follow-up questions, waits for user response
"""

import logging
from openai import AsyncOpenAI
from config import DASHSCOPE_API_KEY, DASHSCOPE_BASE_URL, QWEN_TEXT_MODEL
from utils import retry_async

logger = logging.getLogger(__name__)


FOLLOWUP_SYSTEM_PROMPT = """你是晶肤医美的AI美肤助手"小肤"。

根据刚才的皮肤分析结果，你需要向用户提出2-3个针对性的追问，以便更精准地匹配合适的医美项目。

追问要点：
- 痘印：是近期新留下的还是多年的旧印？
- 色斑：是否晒太阳后加重？什么时候开始出现的？
- 毛孔：T区（额头鼻子）是否更明显？
- 皮肤敏感度：是否容易泛红、刺痛？
- 过敏史：对什么成分或药物过敏？
- 之前是否做过医美项目？

追问要求：
- 一次只问2-3个问题，不要太多
- 语气温暖自然，像朋友关心的询问
- 不要用专业术语堆砌
- 如果用户之前已经回答过相关内容，就不要再重复问"""


async def _call_followup_api(check_msg: str) -> str:
    client = AsyncOpenAI(
        api_key=DASHSCOPE_API_KEY,
        base_url=DASHSCOPE_BASE_URL,
        timeout=60.0,
    )

    response = await client.chat.completions.create(
        model=QWEN_TEXT_MODEL,
        messages=[
            {"role": "system", "content": FOLLOWUP_SYSTEM_PROMPT},
            {"role": "user", "content": check_msg}
        ],
        stream=False,
        temperature=0.7,
        max_tokens=512
    )

    return response.choices[0].message.content


async def ask_followup(analysis_result: str, user_reply: str) -> dict:
    try:
        if user_reply:
            confirm_keywords = [
                "确认", "是的", "可以了", "就这样吧", "推荐项目", "直接推荐",
                "没问题", "不用问了", "别问了", "开始吧", "匹配项目", "给我推荐",
                "介绍项目", "有什么项目", "帮我推荐", "想了解项目", "给我方案",
                "没错", "是的是的", "对的对的",
                "proceed", "confirm", "go ahead",
            ]
            reply_lower = user_reply.lower().strip()
            force_confirm = any(kw in reply_lower for kw in confirm_keywords)

            if len(reply_lower) <= 5:
                force_confirm = False

            if force_confirm:
                logger.info("用户快速确认需求")
                return {
                    "confirmed": True,
                    "message": f"用户确认了需求：{user_reply}",
                    "error": False,
                }

            if not analysis_result or len(analysis_result.strip()) < 20:
                return {
                    "confirmed": False,
                    "message": "请先描述您的皮肤状况或上传照片，我来帮您分析",
                    "error": False,
                }

            check_msg = (
                f"用户的皮肤分析结果：{analysis_result}\n"
                f"用户对追问的回复：{user_reply}\n"
                f"请判断：用户的回复是否明确表达了确认需求、希望直接看到方案推荐？"
                f"如果用户只是简单打招呼（如'你好'、'hi'）、提问、或表达新问题，应返回 confirmed: false。"
                f"只有用户明确表达了确认意愿（如'好的给我推荐'、'确认'、'是的开始吧'等）才返回 confirmed: true。"
                f"以JSON格式回复：{{\"confirmed\": true/false, \"message\": \"你的回复内容\"}}"
            )
        else:
            check_msg = (
                f"这是对用户皮肤的初步分析：{analysis_result}\n"
                f"请提出2-3个针对性的追问来更好地了解用户需求。"
                f"以JSON格式回复：{{\"confirmed\": false, \"message\": \"你的追问内容\"}}"
            )

        logger.info("开始生成追问")
        raw_content = await retry_async(_call_followup_api, check_msg)
        logger.info(f"追问生成完成，原始内容: {repr(raw_content[:200])}")

        import json
        import re

        json_match = re.search(r'\{.*\}', raw_content, re.DOTALL)
        if json_match:
            try:
                parsed = json.loads(json_match.group(0))
                logger.info(f"解析到的 JSON: {repr(parsed)}")
                message = parsed.get("message", "")
                if isinstance(message, str) and message.strip().startswith('{'):
                    try:
                        nested = json.loads(message)
                        message = nested.get("message", message)
                    except:
                        pass
                if not isinstance(message, str):
                    message = str(message)
                result = {
                    "confirmed": bool(parsed.get("confirmed", False)),
                    "message": message,
                    "error": False,
                }
                logger.info(f"最终返回结果: confirmed={result['confirmed']}, message={repr(result['message'][:200])}")
            except json.JSONDecodeError as e:
                logger.warning(f"JSON 解析失败: {e}, 使用原始内容")
                result = {"confirmed": False, "message": str(raw_content), "error": False}
        else:
            logger.info("没有找到 JSON，使用原始内容")
            result = {"confirmed": False, "message": str(raw_content), "error": False}

        if not user_reply:
            result["confirmed"] = False

        if not isinstance(result["message"], str):
            result["message"] = str(result["message"])

        return result

    except Exception as e:
        logger.exception("追问生成失败")
        error_type = type(e).__name__
        return {
            "confirmed": False,
            "message": "抱歉，我暂时无法处理您的回复，请稍后重试",
            "error": True,
            "error_type": f"ask_followup/{error_type}",
        }
EOF

# ---------- 后端: agent/nodes/match_product.py ----------
cat > "$BASE/backend/agent/nodes/match_product.py" << 'EOF'
"""
Node 3 — Product Matching (match_product)
Input: user's confirmed needs
Output: top matching Crystal Dermatology projects with descriptions and pricing
"""

import traceback
from rag.chroma_store import search_similar
from knowledge.projects import KNOWLEDGE


async def match_product(user_needs: str) -> dict:
    try:
        matches = search_similar(user_needs, top_k=2)

        if not matches:
            return {
                "recommendations": KNOWLEDGE[:2],
                "message": "根据您的需求，为您推荐以下项目（建议到店面诊后确定最佳方案）：",
                "error": False,
            }

        return {
            "recommendations": matches,
            "message": f"根据您提到的需求，为您精准匹配了以下 {len(matches)} 个项目（效果因人而异，具体以医生面诊为准）：",
            "error": False,
        }

    except Exception as e:
        traceback.print_exc()
        error_type = type(e).__name__
        return {
            "recommendations": KNOWLEDGE[:2],
            "message": f"智能匹配暂时遇到问题，以下是根据常见需求为您推荐的项目：",
            "error": True,
            "error_type": f"match_product/{error_type}",
        }
EOF

# ---------- 后端: agent/nodes/generate_preview.py ----------
cat > "$BASE/backend/agent/nodes/generate_preview.py" << 'EOF'
"""
Node 4 — Effect Preview Generation (generate_preview)
Input: user's original photo (base64 data URI or URL) + improvement prompts
Output: AI-generated simulated effect image via Seedream 4.5
"""

import os
import uuid
import logging
import aiohttp
from config import ARK_API_KEY, ARK_BASE_URL, ARK_IMAGE_MODEL
from utils import retry_async

logger = logging.getLogger(__name__)


PREVIEW_PROMPT_TEMPLATE = (
    "保持人物面部特征和五官完全不变，仅对皮肤做以下改善：{improvements}。"
    "自然效果，不要变形，不要换脸，不要改变发型、服装、背景。"
    "高清写实摄影风格，冷白皮质感"
)

SEEDREAM_ENDPOINT = f"{ARK_BASE_URL}/images/generations"


async def _call_preview_api(
    prompt: str,
    image_url: str,
    n: int,
    size: str,
) -> list[str]:
    payload = {
        "model": ARK_IMAGE_MODEL,
        "prompt": prompt,
        "image": image_url,
        "size": size,
        "watermark": False,
        "response_format": "url",
    }

    async with aiohttp.ClientSession() as session:
        async with session.post(
            SEEDREAM_ENDPOINT,
            headers={
                "Authorization": f"Bearer {ARK_API_KEY}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=aiohttp.ClientTimeout(total=120),
        ) as response:
            if response.status == 200:
                data = await response.json()
                return [img["url"] for img in data.get("data", [])]
            else:
                body = await response.text()
                raise Exception(f"HTTP {response.status}: {body}")


async def generate_preview(
    improvements: str,
    image_url: str = "",
    n: int = 1,
    size: str = "2K",
) -> dict:
    if not image_url:
        return {
            "success": False,
            "image_urls": [],
            "message": "未提供原始照片，无法生成效果模拟图",
            "error": True,
            "error_type": "generate_preview/missing_image",
        }

    if not ARK_API_KEY:
        return {
            "success": False,
            "image_urls": [],
            "message": "火山方舟 API Key 未配置，效果图生成不可用",
            "error": True,
            "error_type": "generate_preview/no_api_key",
        }

    try:
        prompt = PREVIEW_PROMPT_TEMPLATE.format(improvements=improvements)

        logger.info("开始生成效果图")
        urls = await retry_async(_call_preview_api, prompt, image_url, n, size)
        logger.info("效果图生成完成")

        return {
            "success": True,
            "image_urls": urls,
            "message": "效果模拟图已生成（基于您的照片，Seedream 4.5）",
            "error": False,
        }

    except Exception as e:
        logger.exception("效果图生成失败")

        error_type = type(e).__name__
        error_messages = {
            "TimeoutError": "效果图生成超时，请稍后重试",
            "ClientConnectorError": "无法连接火山方舟服务，请检查网络",
        }
        return {
            "success": False,
            "image_urls": [],
            "message": error_messages.get(error_type, f"效果图暂时无法生成：{str(e)}"),
            "error": True,
            "error_type": f"generate_preview/{error_type}",
        }


def _http_status_text(code: int) -> str:
    m = {
        400: "请求参数错误",
        401: "认证失败",
        403: "权限不足",
        429: "请求过于频繁",
        500: "服务器内部错误",
    }
    return m.get(code, f"HTTP {code}")
EOF

# ---------- 后端: agent/nodes/book_appointment.py ----------
cat > "$BASE/backend/agent/nodes/book_appointment.py" << 'EOF'
"""
Node 5 — Appointment Booking (book_appointment)
Input: final recommended plan
Output: Crystal Dermatology store list + booking entry
(Demo: mock data, directs users to official website for actual booking)
"""

import traceback

MOCK_STORES = [
    {"name": "晶肤医美·成都春熙路店", "address": "成都市锦江区春熙路99号", "phone": "028-88886666"},
    {"name": "晶肤医美·成都万象城店", "address": "成都市成华区双庆路8号", "phone": "028-88887777"},
    {"name": "晶肤医美·成都高新店", "address": "成都市高新区天府大道北段1700号", "phone": "028-88889999"},
]


async def book_appointment(recommendations: list) -> dict:
    try:
        store_list = "\n".join([
            f"🏥 {s['name']}\n📍 {s['address']}\n📞 {s['phone']}"
            for s in MOCK_STORES
        ])

        project_names = "、".join([r.get("name", "推荐项目") for r in recommendations])

        message = (
            f"根据刚才的分析，您可能适合了解：{project_names}\n\n"
            f"晶肤医美在成都有多家门店，以下是最近的几家：\n\n"
            f"{store_list}\n\n"
            f"📋 预约功能开发中，您可以：\n"
            f"1. 拨打上方门店电话直接预约\n"
            f"2. 访问晶肤官网 jfur.com 在线预约\n"
            f"3. 直接到店咨询（建议携带身份证）\n\n"
            f"💡 小肤提醒：到店后医生会根据您的实际情况制定个性化方案，"
            f"所有方案以医生面诊为准哦～"
        )

        return {
            "stores": MOCK_STORES,
            "message": message,
            "error": False,
        }

    except Exception as e:
        traceback.print_exc()
        error_type = type(e).__name__
        return {
            "stores": MOCK_STORES,
            "message": (
                f"根据您的需求，建议您到店详细了解适合的项目。\n\n"
                f"晶肤医美在成都有多家门店：\n\n"
                f"🏥 晶肤医美·成都春熙路店\n📍 成都市锦江区春熙路99号\n📞 028-88886666\n\n"
                f"📋 预约功能开发中，您可以拨打门店电话直接预约"
            ),
            "error": True,
            "error_type": f"book_appointment/{error_type}",
        }
EOF

# ---------- 后端: knowledge/projects.py ----------
cat > "$BASE/backend/knowledge/projects.py" << 'EOF'
import json
from pathlib import Path

KNOWLEDGE = [
    {
        "name": "光子嫩肤",
        "suitable": "肤色暗沉、浅层色斑、红血丝、细小皱纹、毛孔粗大",
        "principle": "强脉冲光穿透皮肤，分解色素、闭合异常毛细血管、刺激胶原再生",
        "price": "1500-2500元/次",
        "recovery": "无恢复期，当天轻微泛红可消退",
        "qa": [
            "光子嫩肤疼吗？基本不疼，像皮筋弹到皮肤的感觉。",
            "做几次有效果？一般3-5次一个疗程，每次间隔一个月。"
        ]
    },
    {
        "name": "果酸焕肤",
        "suitable": "痘痘、痘印、毛孔粗大、皮肤粗糙、油脂分泌旺盛",
        "principle": "不同浓度果酸促进老化角质脱落，加速皮肤更新，改善肤质",
        "price": "800-1500元/次",
        "recovery": "1-2天微红脱屑",
        "qa": [
            "敏感肌能做吗？医生会根据皮肤情况选择适合的浓度。",
            "做完能化妆吗？建议24小时后再化妆。"
        ]
    },
    {
        "name": "水光针",
        "suitable": "皮肤干燥、缺水、细纹、肤色不均、毛孔粗大",
        "principle": "将透明质酸等营养成分直接注入真皮层，深层补水保湿",
        "price": "2000-4000元/次",
        "recovery": "针眼当天消退，可正常护肤",
        "qa": [
            "水光针有副作用吗？短时间可能轻微红肿淤青，很快消退。",
            "能维持多久？一般1-3个月，建议按疗程打效果更好。"
        ]
    },
    {
        "name": "超皮秒",
        "suitable": "各类色斑（雀斑、晒斑、褐青色痣等）、纹身、肤色暗沉",
        "principle": "超短脉冲激光瞬间击碎色素颗粒，由身体代谢排出",
        "price": "3000-6000元/次",
        "recovery": "结痂7-10天脱落，期间注意防晒",
        "qa": [
            "会不会反黑？术后严格防晒很重要，医生会指导护理。",
            "几次能祛干净？看斑的类型和深度，通常2-5次。"
        ]
    },
    {
        "name": "除皱瘦脸针",
        "suitable": "动态纹（鱼尾纹、抬头纹、川字纹）、咬肌肥大",
        "principle": "阻断神经肌肉信号传递，减少肌肉活动，达到除皱和瘦脸效果",
        "price": "2000-5000元/次",
        "recovery": "无恢复期，当天即可正常活动",
        "qa": [
            "会脸僵吗？正规医生操作表情依然自然。",
            "能维持多久？一般4-6个月，可定期补打。"
        ]
    }
]


def get_knowledge_docs():
    docs = []
    for item in KNOWLEDGE:
        doc_text = (
            f"项目名称：{item['name']}\n"
            f"适用人群：{item['suitable']}\n"
            f"治疗原理：{item['principle']}\n"
            f"参考价格：{item['price']}\n"
            f"恢复期：{item['recovery']}\n"
            f"常见问答：{'；'.join(item['qa'])}"
        )
        docs.append({"text": doc_text, "metadata": item})
    return docs
EOF

# ---------- 后端: rag/chroma_store.py ----------
cat > "$BASE/backend/rag/chroma_store.py" << 'EOF'
"""
ChromaDB RAG module — initializes the vector database with knowledge docs.
Uses BAAI/bge-small-zh-v1.5 for Chinese-friendly embeddings (512 dims).
"""

import os
os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")

import chromadb
from chromadb.config import Settings
from sentence_transformers import SentenceTransformer
from config import CHROMA_DB_PATH, BGE_MODEL
from knowledge.projects import get_knowledge_docs

COLLECTION_NAME = "jfur_projects"

_embedding_model = None
_chroma_client = None
_collection = None


def get_embedding_model() -> SentenceTransformer:
    global _embedding_model
    if _embedding_model is None:
        _embedding_model = SentenceTransformer(BGE_MODEL)
    return _embedding_model


def get_chroma_collection():
    global _chroma_client, _collection
    if _collection is None:
        os.makedirs(CHROMA_DB_PATH, exist_ok=True)
        _chroma_client = chromadb.PersistentClient(path=CHROMA_DB_PATH)
        _collection = _chroma_client.get_or_create_collection(
            name=COLLECTION_NAME,
            metadata={"hnsw:space": "cosine"}
        )
    return _collection


def init_knowledge_base():
    col = get_chroma_collection()
    model = get_embedding_model()
    docs = get_knowledge_docs()

    ids = []
    embeddings = []
    documents = []
    metadatas = []

    for i, doc in enumerate(docs):
        ids.append(f"proj_{i}")
        embeddings.append(model.encode(doc["text"]).tolist())
        documents.append(doc["text"])
        metadatas.append(doc["metadata"])

    col.upsert(ids=ids, embeddings=embeddings, documents=documents, metadatas=metadatas)
    return len(docs)


def search_similar(query: str, top_k: int = 2):
    col = get_chroma_collection()
    model = get_embedding_model()
    query_vec = model.encode(query).tolist()
    results = col.query(query_embeddings=[query_vec], n_results=top_k)
    if not results["metadatas"] or not results["metadatas"][0]:
        return []
    out = []
    for meta in results["metadatas"][0]:
        out.append(meta)
    return out
EOF

# ---------- 后端: utils/retry.py ----------
cat > "$BASE/backend/utils/retry.py" << 'EOF'
"""
API 调用重试工具
"""
import asyncio
import logging
from typing import Callable, TypeVar, Any
from functools import wraps

from config import API_RETRY_TIMES, API_RETRY_DELAY

logger = logging.getLogger(__name__)

T = TypeVar('T')


async def retry_async(
    func: Callable[..., T],
    *args: Any,
    retries: int = API_RETRY_TIMES,
    delay: float = API_RETRY_DELAY,
    **kwargs: Any
) -> T:
    last_exception = None

    for attempt in range(retries + 1):
        try:
            return await func(*args, **kwargs)
        except Exception as e:
            last_exception = e
            if attempt < retries:
                logger.warning(
                    f"API 调用失败 (尝试 {attempt + 1}/{retries + 1}): {str(e)}"
                )
                logger.warning(f"将在 {delay} 秒后重试...")
                await asyncio.sleep(delay)
            else:
                logger.error(
                    f"API 调用失败，已达到最大重试次数 ({retries + 1} 次)"
                )

    raise last_exception
EOF

# ---------- 后端: utils/cleanup.py ----------
cat > "$BASE/backend/utils/cleanup.py" << 'EOF'
"""
图片清理工具
定时清理 uploads 目录下的过期文件
"""
import os
import time
import asyncio
import logging
from pathlib import Path
from datetime import datetime, timedelta
from typing import Optional

logger = logging.getLogger(__name__)


def cleanup_old_files(
    uploads_dir: str | Path,
    hours: int = 24,
    dry_run: bool = False
) -> dict:
    uploads_path = Path(uploads_dir)
    if not uploads_path.exists():
        logger.warning(f"目录不存在: {uploads_dir}")
        return {"deleted": 0, "skipped": 0, "errors": 0}

    cutoff_time = datetime.now() - timedelta(hours=hours)
    stats = {"deleted": 0, "skipped": 0, "errors": 0, "total": 0}

    for file_path in uploads_path.iterdir():
        if not file_path.is_file():
            continue

        stats["total"] += 1

        try:
            mtime = datetime.fromtimestamp(file_path.stat().st_mtime)

            if mtime < cutoff_time:
                if dry_run:
                    logger.info(f"[试运行] 会删除: {file_path.name} (最后修改: {mtime})")
                else:
                    file_path.unlink()
                    logger.info(f"已删除过期文件: {file_path.name} (最后修改: {mtime})")
                stats["deleted"] += 1
            else:
                stats["skipped"] += 1
        except Exception as e:
            logger.exception(f"处理文件失败: {file_path.name}")
            stats["errors"] += 1

    logger.info(
        f"清理完成 - 共扫描 {stats['total']} 个文件, "
        f"删除 {stats['deleted']} 个, "
        f"保留 {stats['skipped']} 个, "
        f"错误 {stats['errors']} 个"
    )
    return stats


async def periodic_cleanup_task(
    uploads_dir: str | Path,
    hours: int = 24,
    interval_seconds: int = 3600
):
    logger.info(f"定时清理任务已启动 - 每 {interval_seconds} 秒检查一次, 保留 {hours} 小时内的文件")

    while True:
        try:
            cleanup_old_files(uploads_dir, hours)
        except Exception as e:
            logger.exception("定时清理任务出错")

        await asyncio.sleep(interval_seconds)
EOF

# ---------- 后端: utils/__init__.py ----------
cat > "$BASE/backend/utils/__init__.py" << 'EOF'
"""
工具模块
"""
from .retry import retry_async

__all__ = ['retry_async']
EOF

# ============================================================
# 创建前端文件
# ============================================================

# ---------- 前端: package.json ----------
cat > "$BASE/frontend/package.json" << 'EOF'
{
  "name": "jfur-ai-skincare",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint"
  },
  "dependencies": {
    "@ai-sdk/react": "^0.0.50",
    "@radix-ui/react-avatar": "^1.1.0",
    "@radix-ui/react-scroll-area": "^1.1.0",
    "@radix-ui/react-slot": "^1.1.0",
    "ai": "^3.4.0",
    "class-variance-authority": "^0.7.0",
    "clsx": "^2.1.0",
    "localtunnel": "^2.0.2",
    "lucide-react": "^0.400.0",
    "next": "^14.2.0",
    "react": "^18.3.0",
    "react-dom": "^18.3.0",
    "tailwind-merge": "^2.3.0"
  },
  "devDependencies": {
    "@types/node": "^20.14.0",
    "@types/react": "^18.3.0",
    "@types/react-dom": "^18.3.0",
    "autoprefixer": "^10.4.0",
    "postcss": "^8.4.0",
    "tailwindcss": "^3.4.0",
    "typescript": "^5.5.0"
  }
}
EOF

# ---------- 前端: next.config.js ----------
cat > "$BASE/frontend/next.config.js" << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "**" }
    ]
  }
};

module.exports = nextConfig;
EOF

# ---------- 前端: postcss.config.js ----------
cat > "$BASE/frontend/postcss.config.js" << 'EOF'
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};
EOF

# ---------- 前端: tsconfig.json ----------
cat > "$BASE/frontend/tsconfig.json" << 'EOF'
{
  "compilerOptions": {
    "target": "ES2017",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{"name": "next"}],
    "paths": {
      "@/*": ["./*"]
    }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
EOF

# ---------- 前端: tailwind.config.ts ----------
cat > "$BASE/frontend/tailwind.config.ts" << 'EOF'
import type { Config } from "tailwindcss"

const config: Config = {
  content: [
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          50: "#f0f7ff",
          100: "#e0effe",
          200: "#baddfd",
          300: "#7ec2fc",
          400: "#3aa3f8",
          500: "#1088e9",
          600: "#046bc7",
          700: "#0555a1",
          800: "#094985",
          900: "#0d3d6e",
        },
        jfur: {
          primary: "#2B5F8A",
          accent: "#D4A853",
          light: "#F7F3EB",
          dark: "#1A3A56",
        }
      },
      fontFamily: {
        sans: ["var(--font-sans)", "system-ui", "sans-serif"],
      },
    },
  },
  plugins: [],
};
export default config;
EOF

# ---------- 前端: app/layout.tsx ----------
cat > "$BASE/frontend/app/layout.tsx" << 'EOF'
import type { Metadata } from "next"
import "./globals.css"

export const metadata: Metadata = {
  title: "晶肤AI美肤助手 - 小肤",
  description: "AI美肤助手，上传面部照片，分析皮肤表面特征，匹配晶肤医美项目方案",
  icons: { icon: "/favicon.ico" },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="zh-CN">
      <body className="min-h-screen bg-[#f5f2eb] antialiased">
        {children}
      </body>
    </html>
  )
}
EOF

# ---------- 前端: app/globals.css ----------
cat > "$BASE/frontend/app/globals.css" << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  :root {
    --background: 250 33% 98%;
    --foreground: 222 47% 15%;
    --muted: 240 5% 96%;
    --muted-foreground: 215 16% 47%;
    --card: 0 0% 100%;
    --card-foreground: 222 47% 15%;
    --border: 214 32% 91%;
    --primary: 208 50% 36%;
    --primary-foreground: 210 40% 98%;
    --accent: 42 50% 55%;
    --accent-foreground: 42 50% 20%;
    --radius: 0.75rem;
  }
}

@layer base {
  * {
    @apply border-[hsl(214,32%,91%)];
  }
  body {
    @apply bg-[hsl(250,33%,98%)] text-[hsl(222,47%,15%)];
    font-feature-settings: "rlig" 1, "calt" 1;
  }
}

@keyframes blink {
  0%, 100% { opacity: 1; }
  50% { opacity: 0; }
}

.typing-cursor::after {
  content: "\25AD";
  animation: blink 1s infinite;
}

.custom-scrollbar::-webkit-scrollbar {
  width: 6px;
}
.custom-scrollbar::-webkit-scrollbar-track {
  background: transparent;
}
.custom-scrollbar::-webkit-scrollbar-thumb {
  background: hsl(214, 15%, 85%);
  border-radius: 3px;
}
.custom-scrollbar::-webkit-scrollbar-thumb:hover {
  background: hsl(214, 15%, 75%);
}

.card-hover {
  @apply transition-all duration-200 hover:shadow-md;
}

.message-content p {
  margin-bottom: 0.5rem;
}
.message-content p:last-child {
  margin-bottom: 0;
}
.message-content ul {
  margin: 0.5rem 0;
  padding-left: 1.25rem;
  list-style-type: disc;
}
.message-content li {
  margin-bottom: 0.25rem;
}
EOF

# ---------- 前端: app/page.tsx ----------
cat > "$BASE/frontend/app/page.tsx" << 'EOF'
"use client"

import { useState, useRef, useEffect, useCallback } from "react"
import { Send, ImagePlus, X, Sparkles } from "lucide-react"
import Image from "next/image"
import type { Message } from "@/lib/types"
import { TopBar } from "@/components/chat/TopBar"
import { UserBubble } from "@/components/chat/UserBubble"
import { AnalysisCard } from "@/components/chat/AnalysisCard"
import { FollowupCard } from "@/components/chat/FollowupCard"
import { RecommendationCard } from "@/components/chat/RecommendationCard"
import { PreviewCard } from "@/components/chat/PreviewCard"
import { BookingCard } from "@/components/chat/BookingCard"
import { StatusBubble } from "@/components/chat/StatusBubble"
import { EmptyState } from "@/components/chat/EmptyState"
import { ErrorBoundary } from "@/components/ErrorBoundary"

const API_URL = process.env.NEXT_PUBLIC_API_URL || ""

export default function Home() {
  const [messages, setMessages] = useState<Message[]>([])
  const [inputText, setInputText] = useState("")
  const [uploadedImage, setUploadedImage] = useState<File | null>(null)
  const [imagePreview, setImagePreview] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [statusText, setStatusText] = useState("")
  const [threadId, setThreadId] = useState<string | null>(null)

  const messagesEndRef = useRef<HTMLDivElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const inputTextRef = useRef(inputText)
  inputTextRef.current = inputText

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [messages, statusText])

  const handleImageUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      setUploadedImage(file)
      setImagePreview(URL.createObjectURL(file))
    }
  }

  const removeImage = () => {
    setUploadedImage(null)
    if (imagePreview) {
      URL.revokeObjectURL(imagePreview)
      setImagePreview(null)
    }
    if (fileInputRef.current) {
      fileInputRef.current.value = ""
    }
  }

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    const file = e.dataTransfer.files?.[0]
    if (file && file.type.startsWith("image/")) {
      setUploadedImage(file)
      setImagePreview(URL.createObjectURL(file))
    }
  }, [])

  const processSSE = async (response: Response) => {
    const reader = response.body?.getReader()
    if (!reader) return

    const decoder = new TextDecoder()
    let buffer = ""

    while (true) {
      const { done, value } = await reader.read()
      if (done) break

      buffer += decoder.decode(value, { stream: true })
      const lines = buffer.split("\n")
      buffer = lines.pop() || ""

      let currentEvent = ""

      for (const line of lines) {
        if (line.startsWith("event: ")) {
          currentEvent = line.slice(7).trim()
        } else if (line.startsWith("data: ")) {
          try {
            const data = JSON.parse(line.slice(6))

            const getSafeString = (val: any): string => {
              if (typeof val === 'string') return val
              if (val === null || val === undefined) return ''
              try {
                const seen = new WeakSet()
                return JSON.stringify(val, (key, value) => {
                  if (typeof value === 'object' && value !== null) {
                    if (seen.has(value)) return '[Circular]'
                    seen.add(value)
                  }
                  return value
                }, 2)
              } catch {
                return '[无法显示的内容]'
              }
            }

            switch (currentEvent) {
              case "status":
                setStatusText(getSafeString(data.content))
                break

              case "analysis":
                setStatusText("")
                setMessages(prev => [...prev, {
                  id: crypto.randomUUID(),
                  role: "ai",
                  type: "analysis",
                  content: getSafeString(data.content),
                  disclaimer: data.disclaimer,
                  step: data.step,
                }])
                break

              case "followup":
                setStatusText("")
                setThreadId(data.thread_id || null)
                setMessages(prev => [...prev, {
                  id: crypto.randomUUID(),
                  role: "ai",
                  type: "followup",
                  content: getSafeString(data.content),
                  step: data.step,
                }])
                break

              case "recommendation":
                setStatusText("")
                setMessages(prev => [...prev, {
                  id: crypto.randomUUID(),
                  role: "ai",
                  type: "recommendation",
                  content: getSafeString(data.content),
                  recommendations: data.recommendations || [],
                  step: data.step,
                }])
                break

              case "review":
                setStatusText("")
                setMessages(prev => [...prev, {
                  id: crypto.randomUUID(),
                  role: "system",
                  type: "text",
                  content: getSafeString(data.content),
                }])
                break

              case "preview":
                setStatusText("")
                setMessages(prev => [...prev, {
                  id: crypto.randomUUID(),
                  role: "ai",
                  type: "preview",
                  content: getSafeString(data.content),
                  image_urls: data.image_urls || [],
                  disclaimer: data.disclaimer,
                  step: data.step,
                }])
                break

              case "booking":
                setStatusText("")
                setMessages(prev => [...prev, {
                  id: crypto.randomUUID(),
                  role: "ai",
                  type: "booking",
                  content: getSafeString(data.content),
                  stores: data.stores || [],
                  step: data.step,
                }])
                break

              case "error":
                setStatusText("")
                setMessages(prev => [...prev, {
                  id: crypto.randomUUID(),
                  role: "system",
                  type: "text",
                  content: `❌ ${getSafeString(data.content)}`,
                }])
                break

              case "done":
                setStatusText("")
                setIsLoading(false)
                break
            }
          } catch {}
        }
      }
    }
  }

  const sendMessage = async (overrideText?: any) => {
    const safeOverride = typeof overrideText === 'string' ? overrideText : undefined
    const textToSend = safeOverride || inputTextRef.current.trim()
    if (!textToSend && !uploadedImage) return
    if (isLoading) return

    const userMsg: Message = {
      id: crypto.randomUUID(),
      role: "user",
      type: "text",
      content: String(textToSend || "请帮我分析我的皮肤状况"),
      image_preview: imagePreview,
    }

    setMessages(prev => [...prev, userMsg])
    setInputText("")
    setIsLoading(true)
    setStatusText("🔍 正在处理您的请求...")

    const formData = new FormData()
    const msgList = messages.concat(userMsg).map(m => ({
      role: m.role,
      content: m.content,
    }))
    formData.append("messages", JSON.stringify(msgList))

    if (uploadedImage) {
      formData.append("image", uploadedImage)
    }

    if (threadId) {
      formData.append("thread_id", threadId)
    }

    removeImage()

    try {
      const response = await fetch(`${API_URL}/api/chat`, {
        method: "POST",
        body: formData,
      })
      await processSSE(response)
    } catch (err) {
      setMessages(prev => [...prev, {
        id: crypto.randomUUID(),
        role: "system",
        type: "text",
        content: `❌ 网络错误：无法连接到后端服务。`,
      }])
      setIsLoading(false)
      setStatusText("")
    }
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      sendMessage()
    }
  }

  const renderMessage = (msg: Message) => {
    switch (msg.type) {
      case "analysis":
        return <AnalysisCard message={msg} />
      case "followup":
        return <FollowupCard message={msg} onReply={(text) => {
          setInputText(text)
          setTimeout(() => sendMessage(text), 100)
        }} />
      case "recommendation":
        return <RecommendationCard message={msg} />
      case "preview":
        return <PreviewCard message={msg} />
      case "booking":
        return <BookingCard message={msg} />
      default:
        if (msg.role === "user") {
          return <UserBubble message={msg} />
        }
        return (
          <div className="flex items-start gap-2.5">
            <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#D4A853] to-[#2B5F8A] flex items-center justify-center flex-shrink-0">
              <Sparkles className="w-4 h-4 text-white" />
            </div>
            <div className="max-w-[82%] bg-white rounded-2xl rounded-tl-sm shadow-sm border border-gray-100 px-4 py-2.5">
              <p className="text-sm text-gray-700 leading-relaxed">{msg.content}</p>
            </div>
          </div>
        )
    }
  }

  return (
    <ErrorBoundary>
      <div className="flex flex-col h-screen max-w-3xl mx-auto">
        <TopBar />

        <main className="flex-1 overflow-y-auto custom-scrollbar pt-16 pb-24 px-4">
          {messages.length === 0 && !isLoading && <EmptyState onHintClick={(text) => setInputText(text)} />}
          <div className="space-y-4">
            {messages.map(msg => (
              <div key={msg.id}>{renderMessage(msg)}</div>
            ))}
            {statusText && <StatusBubble text={statusText} />}
          </div>
          <div ref={messagesEndRef} />
        </main>

        <footer className="fixed bottom-0 left-0 right-0 bg-white/80 backdrop-blur-md border-t border-gray-200">
          <div className="max-w-3xl mx-auto px-4 py-3">
            {imagePreview && (
              <div className="mb-2 inline-block relative">
                <div className="w-16 h-16 rounded-lg overflow-hidden border border-gray-200">
                  <Image src={imagePreview} alt="预览" width={64} height={64} className="w-full h-full object-cover" />
                </div>
                <button
                  onClick={removeImage}
                  className="absolute -top-1.5 -right-1.5 w-5 h-5 bg-red-500 text-white rounded-full flex items-center justify-center shadow-sm hover:bg-red-600"
                >
                  <X className="w-3 h-3" />
                </button>
              </div>
            )}

            <div
              className="flex items-end gap-2"
              onDrop={handleDrop}
              onDragOver={(e) => e.preventDefault()}
            >
              <button
                onClick={() => fileInputRef.current?.click()}
                className="flex-shrink-0 w-10 h-10 rounded-full border border-gray-300 flex items-center justify-center text-gray-400 hover:text-[#2B5F8A] hover:border-[#2B5F8A] transition-colors"
                title="上传照片"
              >
                <ImagePlus className="w-5 h-5" />
              </button>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                onChange={handleImageUpload}
                className="hidden"
              />

              <div className="flex-1 relative">
                <input
                  ref={inputRef}
                  type="text"
                  value={inputText}
                  onChange={(e) => setInputText(e.target.value)}
                  onKeyDown={handleKeyDown}
                  placeholder="输入你的皮肤问题..."
                  className="w-full px-4 py-2.5 pr-12 bg-gray-50 border border-gray-200 rounded-2xl text-sm focus:outline-none focus:border-[#2B5F8A] focus:ring-2 focus:ring-[#2B5F8A]/10 transition-all"
                  disabled={isLoading}
                />
              </div>

              <button
                onClick={sendMessage}
                disabled={isLoading || (!inputText.trim() && !uploadedImage)}
                className="flex-shrink-0 w-10 h-10 rounded-full bg-[#2B5F8A] text-white flex items-center justify-center hover:bg-[#1A3A56] transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
              >
                <Send className="w-5 h-5" />
              </button>
            </div>

            <p className="text-center text-xs text-gray-400 mt-2">
              ⚠️ AI分析仅作参考，不能替代专业医生面诊
            </p>
          </div>
        </footer>
      </div>
    </ErrorBoundary>
  )
}
EOF

# ---------- 前端: app/api/chat/route.ts ----------
cat > "$BASE/frontend/app/api/chat/route.ts" << 'EOF'
import { NextRequest } from 'next/server'

export async function POST(request: NextRequest) {
  const BACKEND_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8001'

  try {
    const formData = await request.formData()
    const response = await fetch(`${BACKEND_URL}/api/chat`, {
      method: 'POST',
      body: formData,
    })

    return new Response(response.body, {
      status: response.status,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      },
    })
  } catch (error) {
    return new Response(
      JSON.stringify({ error: 'Failed to connect to backend' }),
      { status: 502, headers: { 'Content-Type': 'application/json' } }
    )
  }
}
EOF

# ---------- 前端: lib/types.ts ----------
cat > "$BASE/frontend/lib/types.ts" << 'EOF'
export interface Message {
  id: string
  role: "user" | "ai" | "system"
  type: "text" | "analysis" | "followup" | "recommendation" | "preview" | "booking" | "status"
  content: string
  recommendations?: Project[]
  stores?: Store[]
  image_urls?: string[]
  image_preview?: string | null
  disclaimer?: string
  step?: string
}

export interface Project {
  name: string
  suitable: string
  principle: string
  price: string
  recovery: string
  qa?: string[]
}

export interface Store {
  name: string
  address: string
  phone: string
}

export const STATUS_STEPS: Record<string, string> = {
  start: "🔍 开始分析您的皮肤状况...",
  analyze: "🔍 正在分析您的皮肤表面特征...",
  ask_followup: "💬 正在进行追问确认...",
  match_product: "📋 正在匹配适合您的项目方案...",
  human_review: "✅ 方案审核通过...",
  generate_preview: "🎨 正在生成效果模拟图...",
  book_appointment: "🏥 正在准备预约引导...",
}
EOF

# ---------- 前端: components/chat/TopBar.tsx ----------
cat > "$BASE/frontend/components/chat/TopBar.tsx" << 'EOF'
export function TopBar() {
  return (
    <header className="fixed top-0 left-0 right-0 z-50 bg-white/80 backdrop-blur-md border-b border-gray-200">
      <div className="max-w-3xl mx-auto px-4 h-14 flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[#2B5F8A] to-[#1A3A56] flex items-center justify-center text-white text-xs font-bold">
            晶
          </div>
          <span className="text-sm font-medium text-gray-500">晶肤医美</span>
        </div>
        <h1 className="text-base font-semibold text-[#2B5F8A] tracking-wide">
          晶肤AI美肤助手
        </h1>
        <div className="w-20" />
      </div>
    </header>
  )
}
EOF

# ---------- 前端: components/chat/UserBubble.tsx ----------
cat > "$BASE/frontend/components/chat/UserBubble.tsx" << 'EOF'
import Image from "next/image"
import type { Message } from "@/lib/types"

export function UserBubble({ message }: { message: Message }) {
  const safeContent = (() => {
    if (typeof message.content === 'string') return message.content
    try {
      const seen = new WeakSet()
      return JSON.stringify(message.content, (key, value) => {
        if (typeof value === 'object' && value !== null) {
          if (seen.has(value)) return '[Circular]'
          seen.add(value)
        }
        return value
      }, 2)
    } catch {
      return '[无法显示的内容]'
    }
  })()

  const safeImagePreview = typeof message.image_preview === 'string'
    ? message.image_preview
    : null

  return (
    <div className="flex justify-end">
      <div className="max-w-[80%] bg-[#2B5F8A] text-white rounded-2xl rounded-br-md px-4 py-2.5 shadow-sm">
        {safeImagePreview && (
          <div className="mb-2 rounded-lg overflow-hidden">
            <Image src={safeImagePreview} alt="上传的照片" width={200} height={200} className="w-full h-auto" />
          </div>
        )}
        <p className="text-sm leading-relaxed whitespace-pre-wrap">{safeContent}</p>
      </div>
    </div>
  )
}
EOF

# ---------- 前端: components/chat/AnalysisCard.tsx ----------
cat > "$BASE/frontend/components/chat/AnalysisCard.tsx" << 'EOF'
"use client"

import { useState, useEffect } from "react"
import { Sparkles } from "lucide-react"
import type { Message } from "@/lib/types"

export function AnalysisCard({ message }: { message: Message }) {
  const [displayText, setDisplayText] = useState("")
  const [isTyping, setIsTyping] = useState(true)

  const safeContent = (() => {
    if (typeof message.content === 'string') return message.content
    try {
      const seen = new WeakSet()
      return JSON.stringify(message.content, (key, value) => {
        if (typeof value === 'object' && value !== null) {
          if (seen.has(value)) return '[Circular]'
          seen.add(value)
        }
        return value
      }, 2)
    } catch {
      return '[无法显示的内容]'
    }
  })()

  useEffect(() => {
    const text = safeContent
    let i = 0
    setDisplayText("")
    const timer = setInterval(() => {
      if (i < text.length) {
        setDisplayText(text.slice(0, i + 1))
        i++
      } else {
        setIsTyping(false)
        clearInterval(timer)
      }
    }, 20)
    return () => clearInterval(timer)
  }, [safeContent])

  return (
    <div className="flex items-start gap-2.5">
      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#D4A853] to-[#2B5F8A] flex items-center justify-center flex-shrink-0">
        <Sparkles className="w-4 h-4 text-white" />
      </div>
      <div className="max-w-[82%] bg-white rounded-2xl rounded-tl-sm shadow-sm border border-gray-100 overflow-hidden">
        <div className="px-4 py-1.5 bg-gradient-to-r from-[#F7F3EB] to-white border-b border-gray-50">
          <span className="text-xs font-medium text-[#2B5F8A]">🔍 皮肤分析结果</span>
        </div>
        <div className="px-4 py-3">
          <p className={`text-sm text-gray-700 leading-relaxed whitespace-pre-wrap ${isTyping ? "typing-cursor" : ""}`}>
            {displayText}
          </p>
        </div>
        {message.disclaimer && !isTyping && (
          <div className="px-4 py-2 bg-amber-50/50 border-t border-amber-100">
            <p className="text-xs text-amber-700">{message.disclaimer}</p>
          </div>
        )}
      </div>
    </div>
  )
}
EOF

# ---------- 前端: components/chat/FollowupCard.tsx ----------
cat > "$BASE/frontend/components/chat/FollowupCard.tsx" << 'EOF'
import { useState } from "react"
import { Sparkles, Send } from "lucide-react"
import type { Message } from "@/lib/types"

export function FollowupCard({ message, onReply }: { message: Message; onReply: (text: string) => void }) {
  const [customReply, setCustomReply] = useState("")

  const safeContent = (() => {
    if (typeof message.content === 'string') return message.content
    try {
      const seen = new WeakSet()
      return JSON.stringify(message.content, (key, value) => {
        if (typeof value === 'object' && value !== null) {
          if (seen.has(value)) return '[Circular]'
          seen.add(value)
        }
        return value
      }, 2)
    } catch {
      return '[无法显示的内容]'
    }
  })()

  const rawLines = safeContent
    .split(/\n/)
    .map((l) => l.trim())
    .filter(Boolean)
  const quickReplies: string[] = rawLines
    .filter((l) => /^\d+[\.\、\)]\s*/.test(l))
    .map((l) => l.replace(/^\d+[\.\、\)]\s*/, ""))

  const handleQuickReply = (text: string) => {
    onReply(String(text))
  }

  const handleCustomReply = (e?: React.MouseEvent | React.KeyboardEvent) => {
    if (e) e.preventDefault()
    if (!customReply.trim()) return
    onReply(String(customReply.trim()))
    setCustomReply("")
  }

  return (
    <div className="flex items-start gap-2.5">
      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#D4A853] to-[#2B5F8A] flex items-center justify-center flex-shrink-0">
        <Sparkles className="w-4 h-4 text-white" />
      </div>
      <div className="max-w-[82%] bg-white rounded-2xl rounded-tl-sm shadow-sm border border-gray-100">
        <div className="px-4 py-1.5 bg-gradient-to-r from-[#F0F7FF] to-white border-b border-gray-50">
          <span className="text-xs font-medium text-[#2B5F8A]">💬 追问确认</span>
        </div>
        <div className="px-4 py-3">
          <p className="text-sm text-gray-700 leading-relaxed whitespace-pre-wrap">{safeContent}</p>
        </div>
        <div className="px-4 pb-2 flex flex-wrap gap-1.5">
          {quickReplies.map((reply, i) => (
            <button
              key={i}
              onClick={() => handleQuickReply(reply)}
              className="text-xs px-3 py-1.5 bg-[#F0F7FF] border border-[#2B5F8A]/20 rounded-full text-[#2B5F8A] hover:bg-[#2B5F8A] hover:text-white transition-colors"
            >
              {reply}
            </button>
          ))}
        </div>
        <div className="px-4 pb-3 flex items-center gap-2">
          <input
            type="text"
            value={customReply}
            onChange={(e) => setCustomReply(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter") handleCustomReply() }}
            placeholder="或输入你的回复..."
            className="flex-1 text-xs px-3 py-1.5 bg-gray-50 border border-gray-200 rounded-full focus:outline-none focus:border-[#2B5F8A] transition-colors"
          />
          <button
            onClick={handleCustomReply}
            disabled={!customReply.trim()}
            className="w-7 h-7 rounded-full bg-[#2B5F8A] text-white flex items-center justify-center hover:bg-[#1A3A56] transition-colors disabled:opacity-40"
          >
            <Send className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>
    </div>
  )
}
EOF

# ---------- 前端: components/chat/RecommendationCard.tsx ----------
cat > "$BASE/frontend/components/chat/RecommendationCard.tsx" << 'EOF'
import { Sparkles } from "lucide-react"
import type { Message } from "@/lib/types"

export function RecommendationCard({ message }: { message: Message }) {
  return (
    <div className="flex items-start gap-2.5">
      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#D4A853] to-[#2B5F8A] flex items-center justify-center flex-shrink-0">
        <Sparkles className="w-4 h-4 text-white" />
      </div>
      <div className="max-w-[82%] space-y-3">
        <p className="text-sm text-gray-700 ml-1">{message.content}</p>
        {message.recommendations?.map((proj, idx) => (
          <div key={idx} className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden card-hover">
            <div className="px-4 py-2 bg-gradient-to-r from-[#F7F3EB] to-white border-b border-gray-50 flex items-center justify-between">
              <span className="text-sm font-semibold text-[#1A3A56]">{proj.name}</span>
              <span className="text-xs font-medium text-[#D4A853] bg-[#FDFBF5] px-2 py-0.5 rounded-full border border-amber-100">
                {proj.price}
              </span>
            </div>
            <div className="px-4 py-3 space-y-2">
              <div>
                <span className="text-xs text-gray-400">适用人群</span>
                <p className="text-sm text-gray-700">{proj.suitable}</p>
              </div>
              <div>
                <span className="text-xs text-gray-400">治疗原理</span>
                <p className="text-sm text-gray-700">{proj.principle}</p>
              </div>
              <div>
                <span className="text-xs text-gray-400">恢复期</span>
                <p className="text-sm text-gray-700">{proj.recovery}</p>
              </div>
              {proj.qa && proj.qa.length > 0 && (
                <div className="mt-2 pt-2 border-t border-gray-100">
                  <span className="text-xs text-gray-400">常见问题</span>
                  {proj.qa.map((q, qIdx) => (
                    <p key={qIdx} className="text-xs text-gray-600 mt-1">💡 {q}</p>
                  ))}
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
EOF

# ---------- 前端: components/chat/PreviewCard.tsx ----------
cat > "$BASE/frontend/components/chat/PreviewCard.tsx" << 'EOF'
import Image from "next/image"
import { Sparkles } from "lucide-react"
import type { Message } from "@/lib/types"

export function PreviewCard({ message }: { message: Message }) {
  return (
    <div className="flex items-start gap-2.5">
      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#D4A853] to-[#2B5F8A] flex items-center justify-center flex-shrink-0">
        <Sparkles className="w-4 h-4 text-white" />
      </div>
      <div className="max-w-[82%] bg-white rounded-2xl rounded-tl-sm shadow-sm border border-gray-100 overflow-hidden">
        <div className="px-4 py-1.5 bg-gradient-to-r from-[#FEF3E8] to-white border-b border-gray-50">
          <span className="text-xs font-medium text-[#D4A853]">🎨 效果模拟图</span>
        </div>
        <div className="p-4">
          {message.image_urls?.map((url, idx) => (
            <div key={idx} className="rounded-lg overflow-hidden">
              <Image src={url} alt={`效果模拟图 ${idx + 1}`} width={512} height={512} className="w-full h-auto" />
            </div>
          ))}
          {message.disclaimer && (
            <p className="text-xs text-amber-600 mt-3 text-center bg-amber-50/50 rounded-lg py-1.5">
              {message.disclaimer}
            </p>
          )}
        </div>
      </div>
    </div>
  )
}
EOF

# ---------- 前端: components/chat/BookingCard.tsx ----------
cat > "$BASE/frontend/components/chat/BookingCard.tsx" << 'EOF'
import { Sparkles, MapPin, Phone } from "lucide-react"
import type { Message } from "@/lib/types"

export function BookingCard({ message }: { message: Message }) {
  const stores = message.stores || []

  return (
    <div className="flex items-start gap-2.5">
      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#D4A853] to-[#2B5F8A] flex items-center justify-center flex-shrink-0">
        <Sparkles className="w-4 h-4 text-white" />
      </div>
      <div className="max-w-[82%] bg-white rounded-2xl rounded-tl-sm shadow-sm border border-gray-100 overflow-hidden">
        <div className="px-4 py-1.5 bg-gradient-to-r from-[#F0FFF4] to-white border-b border-gray-50">
          <span className="text-xs font-medium text-green-700">🏥 预约引导</span>
        </div>
        <div className="px-4 py-3">
          <p className="text-sm text-gray-700 leading-relaxed whitespace-pre-wrap">{message.content}</p>
        </div>
        <div className="px-4 pb-4 flex gap-2">
          <a
            href="https://www.jfur.com"
            target="_blank"
            rel="noopener noreferrer"
            className="flex-1 py-2 bg-[#2B5F8A] text-white text-sm rounded-lg hover:bg-[#1A3A56] transition-colors flex items-center justify-center gap-1.5"
          >
            <MapPin className="w-4 h-4" />
            查看门店
          </a>
          {stores[0]?.phone && (
            <a
              href={`tel:${stores[0].phone}`}
              className="flex-1 py-2 border border-[#2B5F8A] text-[#2B5F8A] text-sm rounded-lg hover:bg-[#F0F7FF] transition-colors text-center"
            >
              <Phone className="w-4 h-4 inline mr-1" />
              拨打电话
            </a>
          )}
        </div>
      </div>
    </div>
  )
}
EOF

# ---------- 前端: components/chat/StatusBubble.tsx ----------
cat > "$BASE/frontend/components/chat/StatusBubble.tsx" << 'EOF'
import { Sparkles } from "lucide-react"

export function StatusBubble({ text }: { text: string }) {
  return (
    <div className="flex items-start gap-2.5">
      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#D4A853] to-[#2B5F8A] flex items-center justify-center flex-shrink-0 animate-pulse">
        <Sparkles className="w-4 h-4 text-white" />
      </div>
      <div className="bg-white/60 backdrop-blur rounded-full px-4 py-1.5 border border-gray-200">
        <p className="text-xs text-gray-500">{text}</p>
      </div>
    </div>
  )
}
EOF

# ---------- 前端: components/chat/EmptyState.tsx ----------
cat > "$BASE/frontend/components/chat/EmptyState.tsx" << 'EOF'
import { Sparkles } from "lucide-react"

export function EmptyState({ onHintClick }: { onHintClick?: (text: string) => void }) {
  const hints = [
    "我想改善痘印和肤色暗沉",
    "T区毛孔粗大怎么办？",
    "推荐什么项目适合敏感肌？",
  ]

  const handleClick = (hint: string) => {
    if (onHintClick) {
      onHintClick(hint)
    }
  }

  return (
    <div className="flex flex-col items-center justify-center py-20 text-gray-400">
      <div className="w-20 h-20 rounded-2xl bg-gradient-to-br from-[#F7F3EB] to-white border border-gray-200 flex items-center justify-center mb-6 shadow-sm">
        <Sparkles className="w-10 h-10 text-[#D4A853]" />
      </div>
      <h2 className="text-lg font-medium text-gray-600 mb-2">你好，我是小肤 ✨</h2>
      <p className="text-sm text-gray-400 text-center max-w-xs">
        上传一张面部照片，告诉我你想改善的皮肤问题，<br />
        我会为你分析并推荐适合的晶肤医美方案
      </p>
      <div className="mt-8 flex flex-wrap gap-2 justify-center max-w-sm">
        {hints.map((hint, i) => (
          <button
            key={i}
            onClick={() => handleClick(hint)}
            className="text-xs px-3 py-1.5 bg-white border border-gray-200 rounded-full text-gray-500 hover:border-[#2B5F8A] hover:text-[#2B5F8A] transition-colors"
          >
            {hint}
          </button>
        ))}
      </div>
    </div>
  )
}
EOF

# ---------- 前端: components/ErrorBoundary.tsx ----------
cat > "$BASE/frontend/components/ErrorBoundary.tsx" << 'EOF'
'use client'

import React, { Component, ReactNode } from 'react'

interface Props {
  children: ReactNode
  fallback?: ReactNode
}

interface State {
  hasError: boolean
  error?: Error
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props)
    this.state = { hasError: false }
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error('ErrorBoundary caught an error:', error, errorInfo)
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback || (
        <div className="flex flex-col items-center justify-center min-h-[400px] p-8 text-center">
          <div className="text-4xl mb-4">😔</div>
          <h2 className="text-xl font-bold mb-2">抱歉，遇到了一些问题</h2>
          <p className="text-gray-600 mb-4">
            {this.state.error?.message || '请尝试刷新页面'}
          </p>
          <button
            onClick={() => window.location.reload()}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
          >
            刷新页面
          </button>
        </div>
      )
    }

    return this.props.children
  }
}
EOF

echo "项目文件创建完成 ✅"

# ============================================================
# 3. 创建环境变量文件
# ============================================================
echo ""
echo "[4/5] 创建环境变量文件..."

cat > "$BASE/backend/.env" << 'EOF'
DASHSCOPE_API_KEY=请替换为你的阿里云百炼API-KEY
ARK_API_KEY=请替换为你的火山方舟API-KEY
CHROMA_DB_PATH=/data/chroma_db
CORS_ALLOWED_ORIGINS=*
EOF

echo "⚠️  请修改 /opt/jfur/backend/.env 填入真实API KEY"

# ============================================================
# 4. 创建 Docker 部署文件
# ============================================================
echo ""
echo "创建 Docker 部署文件..."

# Dockerfile.backend
cat > "$BASE/deploy/Dockerfile.backend" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends gcc g++ curl && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --no-cache-dir aiohttp
COPY backend/ .
EXPOSE 8001
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
EOF

# Dockerfile.frontend
cat > "$BASE/deploy/Dockerfile.frontend" << 'EOF'
FROM node:20-alpine AS deps
WORKDIR /app
COPY frontend/package.json frontend/package-lock.json* ./
RUN npm ci --production 2>/dev/null || npm install --production

FROM node:20-alpine AS builder
WORKDIR /app
COPY frontend/ .
COPY --from=deps /app/node_modules ./node_modules
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nextjs
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3000
CMD ["node", "server.js"]
EOF

# nginx.conf
cat > "$BASE/deploy/nginx.conf" << 'EOF'
worker_processes auto;
events { worker_connections 1024; }
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 20m;
    server {
        listen 80;
        server_name _;
        location / {
            proxy_pass http://frontend:3000;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_read_timeout 300s;
        }
        location /api/ {
            proxy_pass http://backend:8001/api/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_buffering off;
            proxy_cache off;
            proxy_read_timeout 300s;
        }
        location /uploads/ {
            proxy_pass http://backend:8001/uploads/;
            proxy_set_header Host $host;
        }
        location /api/health {
            proxy_pass http://backend:8001/api/health;
            proxy_set_header Host $host;
        }
    }
}
EOF

# docker-compose.yml
cat > "$BASE/deploy/docker-compose.yml" << 'EOF'
services:
  nginx:
    image: nginx:alpine
    container_name: jfur-nginx
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - frontend
      - backend
    restart: unless-stopped
  frontend:
    build:
      context: ..
      dockerfile: deploy/Dockerfile.frontend
    container_name: jfur-frontend
    environment:
      - NEXT_PUBLIC_API_URL=
    depends_on:
      - backend
    restart: unless-stopped
  backend:
    build:
      context: ..
      dockerfile: deploy/Dockerfile.backend
    container_name: jfur-backend
    env_file:
      - ../backend/.env
    environment:
      - CHROMA_DB_PATH=/data/chroma_db
      - UPLOADS_BASE_URL=http://8.154.35.206/uploads
    volumes:
      - jfur_data:/data
      - jfur_uploads:/app/uploads
    restart: unless-stopped
volumes:
  jfur_data:
  jfur_uploads:
EOF

echo "Docker 部署文件创建完成 ✅"

# ============================================================
# 5. 构建并启动
# ============================================================
echo ""
echo "[5/5] 构建 Docker 镜像并启动..."

cd "$BASE"
docker compose -f deploy/docker-compose.yml down 2>/dev/null || true
docker compose -f deploy/docker-compose.yml up -d --build

echo ""
echo "============================================"
echo " 部署完成！"
echo "============================================"
echo ""
echo "访问地址: http://8.154.35.206"
echo ""
echo "常用命令:"
echo "  查看日志:   cd /opt/jfur && docker compose -f deploy/docker-compose.yml logs -f"
echo "  重启服务:   cd /opt/jfur && docker compose -f deploy/docker-compose.yml restart"
echo "  停止服务:   cd /opt/jfur && docker compose -f deploy/docker-compose.yml down"
echo ""
echo "⚠️  别忘了修改 API KEY:"
echo "  vi /opt/jfur/backend/.env"
echo "============================================"
