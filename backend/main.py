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

# 后台任务引用
_cleanup_task = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """FastAPI 生命周期管理"""
    global _cleanup_task

    logger.info("=" * 60)
    logger.info("🚀 晶肤AI美肤助手启动中...")
    logger.info("=" * 60)

    # 验证环境变量
    if not validate_env():
        logger.warning("环境变量未完全配置，部分功能可能不可用")
    else:
        logger.info("✅ 环境变量验证通过")

    # 初始化知识库
    try:
        count = init_knowledge_base()
        logger.info(f"✅ ChromaDB 初始化完成，共 {count} 个项目")
    except Exception as e:
        logger.exception("ChromaDB 初始化失败")

    # 启动图片清理后台任务（每小时检查一次，保留24小时内的文件）
    _cleanup_task = asyncio.create_task(
        periodic_cleanup_task(UPLOADS_DIR, hours=24, interval_seconds=3600)
    )
    logger.info("✅ 定时清理任务已启动")

    logger.info("=" * 60)
    logger.info("✅ 服务启动完成")
    logger.info("=" * 60)

    yield

    # 关闭时清理
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

# 处理 CORS 配置
def get_cors_origins():
    if CORS_ALLOWED_ORIGINS == "*":
        return ["*"]
    # 逗号分隔多个 origin
    return [o.strip() for o in CORS_ALLOWED_ORIGINS.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=get_cors_origins(),
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serve uploaded images as static files so Seedream can access them via public URL
UPLOADS_DIR = Path(__file__).parent / "uploads"
UPLOADS_DIR.mkdir(exist_ok=True)
app.mount("/uploads", StaticFiles(directory=str(UPLOADS_DIR)), name="uploads")


class ChatRequest(BaseModel):
    messages: List[dict]
    image_base64: Optional[str] = None
    thread_id: Optional[str] = None


# ===== SSE Helpers =====
def sse_event(event: str, data: dict) -> str:
    """Format a Server-Sent Event."""
    payload = json.dumps(data, ensure_ascii=False)
    return f"event: {event}\ndata: {payload}\n\n"


async def sse_stream(events):
    """Async generator yielding SSE formatted events."""
    async for evt in events:
        yield sse_event(evt["event"], evt["data"])


async def run_agent_events(image_base64: str | None, image_url: str, user_text: str, conversation_state: dict = None):
    """
    Run the LangGraph agent via app_graph.astream() and yield SSE events.
    The graph handles: [analyze?] → ask_followup → [match_product → ... → booking] or [END]
    """
    app_graph = await get_agent()
    conv_state = conversation_state or {}
    thread_id = conv_state.get("thread_id", str(uuid.uuid4()))

    # Decide: fresh conversation (with photo) vs. resume (user reply to follow-up)
    is_resuming = bool(thread_id and conversation_state and not image_base64)

    if is_resuming:
        # Resume: ONLY pass new user input. The checkpointer preserves all other
        # fields (analysis_result, image_base64, image_url, followup_confirmed, etc.)
        initial_state: dict = {
            "user_text": user_text or "",
            "last_user_reply": user_text or "",
            "messages": [
                {"role": "user", "type": "text", "content": user_text or ""}
            ],
        }
    else:
        # Fresh conversation: set all state fields
        initial_state: dict = {
            "user_text": user_text or "",
            "last_user_reply": user_text or "",
            "messages": conv_state.get("messages", []),
            # Defaults — the graph will fill these in
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
        # Only set image fields when a new image is uploaded
        if image_base64:
            initial_state["image_base64"] = image_base64
            initial_state["image_url"] = image_url

    config = {"configurable": {"thread_id": thread_id}}

    # Step labels for status events
    step_labels = {
        "analyze": "\U0001f50d 正在分析您的皮肤表面特征...",
        "ask_followup": "\U0001f4ac 正在进行追问确认...",
        "match_product": "\U0001f4cb 正在匹配适合您的项目方案...",
        "human_review": "✅ 方案审核通过...",
        "generate_preview": "\U0001f3a8 正在生成效果模拟图...",
        "book_appointment": "\U0001f3e5 正在准备预约引导...",
    }

    try:
        # Initial status — warm the user
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
        already_done = False  # Track if we emitted a mid-flow done event

        # Stream through the LangGraph — each chunk is a node's output
        async for chunk in app_graph.astream(initial_state, config):
            node_name = list(chunk.keys())[0] if isinstance(chunk, dict) and chunk else None
            node_state = chunk.get(node_name, {}) if node_name else {}

            if node_name is None:
                continue

            current_step = node_state.get("current_step", node_name)
            messages = node_state.get("messages", [])

            # Emit status event when stepping into a new node
            if current_step != previous_step:
                label = step_labels.get(current_step, f"⏳ {current_step}")
                yield {
                    "event": "status",
                    "data": {"type": "status", "content": label, "step": current_step}
                }

            # Map node outputs to frontend SSE events
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
                    # User confirmed — the graph will route to match_product next
                    # We don't emit a visible event; just let the status update
                    pass
                else:
                    # Ask the follow-up question, then stop (graph routes to END)
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
                # Emit the review checkpoint message
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

        # Emit final "done" event only if we haven't already terminated mid-flow
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
    """
    验证上传的图片：类型和大小
    返回: 图片字节数据
    抛出: HTTPException 如果验证失败
    """
    if not image:
        return b""

    # 验证文件类型
    content_type = image.content_type or ""
    if content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"不支持的图片类型。支持类型：{', '.join(ALLOWED_IMAGE_TYPES)}"
        )

    # 读取并验证大小
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
    """
    POST /api/chat — multipart/form-data
    - messages: JSON string of chat messages
    - image: uploaded image file
    - thread_id: optional conversation thread ID for continuing a session
    """
    try:
        messages_list = json.loads(messages)
    except json.JSONDecodeError:
        return StreamingResponse(
            sse_stream([{"event": "error", "data": {"type": "error", "content": "messages 格式错误"}}]),
            media_type="text/event-stream"
        )

    # Extract the last user text
    user_text = ""
    for msg in reversed(messages_list):
        if isinstance(msg, dict) and msg.get("role") == "user":
            user_text = msg.get("content", "")
            if isinstance(user_text, list):
                # Multi-modal content — extract text parts
                text_parts = [p.get("text", "") for p in user_text if isinstance(p, dict) and p.get("type") == "text"]
                user_text = " ".join(text_parts)
            break

    # Build base64 data URI for Seedream 4.5 (supports data:image/...;base64,...)
    image_base64 = None
    image_url = ""
    image_bytes = b""
    try:
        if image and image.filename:
            image_bytes = await validate_image(image)
            import base64
            image_base64 = base64.b64encode(image_bytes).decode("utf-8")

            # Determine MIME type — Seedream requires lowercase format in the data URI prefix
            fmt = Path(image.filename).suffix.lstrip(".").lower() or "jpg"
            if fmt == "jpg":
                fmt = "jpeg"
            image_url = f"data:image/{fmt};base64,{image_base64}"

            # Also save to uploads/ for debugging
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
    """
    POST /api/chat/continue — continue a conversation with text reply.
    Used when the agent asks follow-up questions and the user replies.
    """
    user_text = ""
    for msg in reversed(request.messages):
        if isinstance(msg, dict) and msg.get("role") == "user":
            user_text = msg.get("content", "")
            break

    # Use the thread_id from the request to resume the conversation
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
    """
    健康检查端点
    检查：服务状态、数据库连接、环境变量
    """
    checks = {
        "status": "ok",
        "service": "晶肤AI美肤助手",
        "checks": {}
    }

    # 检查环境变量
    try:
        from config import DASHSCOPE_API_KEY
        checks["checks"]["env"] = "ok" if DASHSCOPE_API_KEY else "missing"
    except Exception:
        checks["checks"]["env"] = "error"

    # 检查数据库
    try:
        from rag.chroma_store import get_chroma_collection
        col = get_chroma_collection()
        checks["checks"]["chromadb"] = "ok"
    except Exception:
        checks["checks"]["chromadb"] = "error"

    return checks


# 添加手动清理 API 端点
@app.post("/api/admin/cleanup")
async def manual_cleanup(hours: int = 24, dry_run: bool = False):
    """
    手动触发图片清理

    Args:
        hours: 保留多少小时内的文件
        dry_run: 试运行模式，只统计不删除
    """
    result = cleanup_old_files(UPLOADS_DIR, hours, dry_run)
    return {
        "status": "ok",
        "message": "清理完成" if not dry_run else "试运行完成",
        "result": result
    }
