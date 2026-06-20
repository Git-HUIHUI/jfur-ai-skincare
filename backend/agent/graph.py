"""
LangGraph State Graph — orchestrates the 5-node AI agent workflow.
Flow: analyze → ask_followup (loop until confirmed) → match_product → [human_review] → generate_preview → book_appointment
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
    # User input
    image_base64: str
    image_url: str              # Public URL for Seedream 4.5 (saved from first upload)
    user_text: str
    # Conversation history
    messages: Annotated[Sequence[dict], lambda x, y: list(x) + list(y) if y else x]
    last_user_reply: str  # The most recent user reply (for multi-round conversation)
    # Node outputs
    analysis_result: str
    followup_message: str
    followup_confirmed: bool
    recommendations: list
    recommendation_message: str
    preview_image_urls: list
    preview_message: str
    booking_message: str
    stores: list  # Store info for booking
    # Flow control
    current_step: str
    needs_followup: bool
    # Human review
    approved: bool


# ===== Node Functions =====
async def node_analyze(state: AgentState) -> AgentState:
    """Node 1: Analyze skin from uploaded photo."""
    image_url = state.get("image_url", "")  # Preserve for generate_preview downstream
    result = await analyze_skin(state["image_base64"], state.get("user_text", ""))
    if result.get("error"):
        return {
            "analysis_result": result["content"],
            "image_url": image_url,  # Preserve through checkpoint
            "current_step": "analyze",
            "needs_followup": False,
            "messages": [
                {"role": "ai", "type": "analysis_error", "content": result["content"],
                 "error_type": result.get("error_type", "")}
            ]
        }
    return {
        "analysis_result": result["content"],
        "image_url": image_url,  # Preserve through checkpoint
        "current_step": "analyze",
        "needs_followup": True,
        "messages": [
            {"role": "ai", "type": "analysis", "content": result["content"]}
        ]
    }


async def node_ask_followup(state: AgentState) -> AgentState:
    """Node 2: Generate follow-up questions."""
    user_reply = state.get("last_user_reply", "")
    analysis_result = state.get("analysis_result", "")
    image_url = state.get("image_url", "")  # Preserve image_url in follow-up state
    result = await ask_followup(analysis_result, user_reply)

    followup_confirmed = result.get("confirmed", False)
    followup_message = result.get("message", "")

    # Determine routing: if confirmed, stop asking; otherwise loop back
    if followup_confirmed:
        return {
            "followup_message": followup_message,
            "followup_confirmed": True,
            "needs_followup": False,
            "current_step": "ask_followup",
            "image_url": image_url,  # Preserve through checkpoint
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
            "image_url": image_url,  # Preserve through checkpoint
            "messages": [
                {"role": "ai", "type": "text", "content": followup_message}
            ]
        }


async def node_match_product(state: AgentState) -> AgentState:
    """Node 3: Match user needs to Crystal Dermatology projects."""
    # Build query from analysis + confirmed needs
    query = f"{state.get('analysis_result', '')} {state.get('followup_message', '')}"
    image_url = state.get("image_url", "")  # Preserve through checkpoint
    result = await match_product(query)

    return {
        "recommendations": result["recommendations"],
        "recommendation_message": result["message"],
        "image_url": image_url,  # Preserve for generate_preview
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
    """
    Checkpoint: Human review before generating preview image.
    Demo mode: auto-approve; code logic preserved for real-world use.
    """
    # In production, this would pause and wait for human input via LangGraph Checkpointing
    # For demo: auto-approve after recommendations are matched
    image_url = state.get("image_url", "")  # Preserve through checkpoint
    return {
        "approved": True,
        "image_url": image_url,  # Preserve for generate_preview
        "current_step": "human_review",
        "messages": [
            {"role": "system", "type": "text", "content": "[审核检查点] 方案已自动通过（Demo模式）。实际部署需人工审核。"}
        ]
    }


async def node_generate_preview(state: AgentState) -> AgentState:
    """Node 4: Generate simulated effect image."""
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
    """Node 5: Guide user to book an appointment."""
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
    """
    Conditional entry: skip analyze when the user is replying to a follow-up
    with a confirmation (no new image, confirmation keywords present).
    """
    user_text = (state.get("user_text") or "").lower()
    has_image = bool(state.get("image_base64"))

    # Resume: already have analysis results but haven't confirmed yet
    # → skip re-analysis, go straight to ask_followup
    if state.get("analysis_result") and not state.get("followup_confirmed"):
        return "ask_followup"

    # Always analyze when there's a photo
    if has_image:
        return "analyze"

    # If the user is confirming / asking for recommendations → skip to ask_followup
    confirm_words = [
        "确认", "好的", "推荐给我", "直接推荐", "给我推荐",
        "帮我推荐", "介绍项目", "推荐项目", "给我方案",
    ]
    if any(kw in user_text for kw in confirm_words):
        return "ask_followup"

    # Default: analyze first
    return "analyze"


def route_after_followup(state: AgentState) -> str:
    """Route: if follow-up confirmed → match_product; else → end (wait for user reply)"""
    if state.get("followup_confirmed", False):
        return "match_product"
    return END


def should_skip_preview(state: AgentState) -> str:
    """Route: skip preview if no image available or recommendations empty"""
    if state.get("approved", False):
        return "generate_preview"
    return "book_appointment"


# ===== Build the Graph =====
# AsyncSqliteSaver enables persistent checkpointing — sessions survive restarts
DB_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "chroma_db", "checkpoints.db")

_checkpointer: Optional[AsyncSqliteSaver] = None
_checkpointer_ctx = None  # Keep the async context manager alive


async def _get_async_checkpointer() -> AsyncSqliteSaver:
    """Return a shared AsyncSqliteSaver — the async context manager stays alive."""
    global _checkpointer, _checkpointer_ctx
    if _checkpointer is None:
        _checkpointer_ctx = AsyncSqliteSaver.from_conn_string(DB_PATH)
        _checkpointer = await _checkpointer_ctx.__aenter__()
    return _checkpointer


async def build_graph():
    """Build and compile the LangGraph state graph with SQLite persistence."""
    workflow = StateGraph(AgentState)

    # Add nodes
    workflow.add_node("analyze", node_analyze)
    workflow.add_node("ask_followup", node_ask_followup)
    workflow.add_node("match_product", node_match_product)
    workflow.add_node("human_review", node_human_review)
    workflow.add_node("generate_preview", node_generate_preview)
    workflow.add_node("book_appointment", node_book_appointment)

    # Define edges — use conditional entry to optionally skip analyze
    workflow.add_conditional_edges(
        START,
        route_entry,
        {"analyze": "analyze", "ask_followup": "ask_followup"}
    )
    workflow.add_edge("analyze", "ask_followup")

    # Conditional routing from ask_followup:
    # - If confirmed → proceed to match_product
    # - If not → END (wait for user's reply via API)
    workflow.add_conditional_edges(
        "ask_followup",
        route_after_followup,
        {"match_product": "match_product", END: END}
    )

    workflow.add_edge("match_product", "human_review")
    workflow.add_edge("human_review", "generate_preview")
    workflow.add_edge("generate_preview", "book_appointment")
    workflow.add_edge("book_appointment", END)

    # Compile with SQLite persistent checkpointing (async-safe)
    checkpointer = await _get_async_checkpointer()
    app = workflow.compile(checkpointer=checkpointer)
    return app


# Singleton
_agent_graph = None


async def get_agent():
    global _agent_graph
    if _agent_graph is None:
        _agent_graph = await build_graph()
    return _agent_graph
