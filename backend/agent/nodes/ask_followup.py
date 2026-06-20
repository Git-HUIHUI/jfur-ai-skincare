"""
Node 2 — Follow-up Questions (ask_followup)
Input: analysis result from node 1
Output: targeted follow-up questions, waits for user response
"""

from openai import OpenAI
from config import DASHSCOPE_API_KEY, DASHSCOPE_BASE_URL, QWEN_TEXT_MODEL


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


async def ask_followup(analysis_result: str, user_reply: str) -> dict:
    """
    Generate follow-up questions based on the analysis.
    Returns dict with:
    - confirmed: bool (whether user confirmed and is ready to proceed)
    - message: str (follow-up questions or confirmation message)
    - error: bool (whether an error occurred in this step)
    - error_type: str (machine-readable error type if error)
    """
    try:
        client = OpenAI(
            api_key=DASHSCOPE_API_KEY,
            base_url=DASHSCOPE_BASE_URL,
            timeout=60.0,
        )

        # If user has just replied to previous follow-up, check if they want to proceed
        if user_reply:
            # Fast-path: strong confirmation keywords → skip LLM check, force confirmed
            confirm_keywords = [
                "确认", "是的", "可以了", "就这样吧", "推荐项目", "直接推荐",
                "没问题", "不用问了", "别问了", "开始吧", "匹配项目", "给我推荐",
                "介绍项目", "有什么项目", "帮我推荐", "想了解项目", "给我方案",
                "没错", "是的是的", "对的对的",
                "proceed", "confirm", "go ahead",
            ]
            reply_lower = user_reply.lower().strip()
            force_confirm = any(kw in reply_lower for kw in confirm_keywords)

            # Short message (< 5 chars) like "hi", "?", "你好" — never force confirm
            if len(reply_lower) <= 5:
                force_confirm = False

            if force_confirm:
                # Build a quick confirmation summary without an extra LLM call
                return {
                    "confirmed": True,
                    "message": f"用户确认了需求：{user_reply}",
                    "error": False,
                }

            # Only ask LLM to judge if there's a real analysis to work with
            if not analysis_result or len(analysis_result.strip()) < 20:
                # No analysis available — always ask follow-up questions
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

        response = client.chat.completions.create(
            model=QWEN_TEXT_MODEL,
            messages=[
                {"role": "system", "content": FOLLOWUP_SYSTEM_PROMPT},
                {"role": "user", "content": check_msg}
            ],
            stream=False,
            temperature=0.7,
            max_tokens=512
        )

        import json
        import re
        raw_content = response.choices[0].message.content

        # Strip markdown code fences if present (LLM sometimes wraps JSON in ```json ... ```)
        # Also handle leading/trailing whitespace and extra text
        json_match = re.search(r'\{.*\}', raw_content, re.DOTALL)
        if json_match:
            try:
                result = json.loads(json_match.group(0))
            except json.JSONDecodeError:
                result = {"confirmed": False, "message": raw_content}
        else:
            result = {"confirmed": False, "message": raw_content}

        result["error"] = False
        return result

    except Exception as e:
        import traceback
        traceback.print_exc()
        error_type = type(e).__name__
        return {
            "confirmed": False,
            "message": "抱歉，我暂时无法处理您的回复，请稍后重试",
            "error": True,
            "error_type": f"ask_followup/{error_type}",
        }
