"""
Node 1 — Skin Analysis (analyze)
Input: user's uploaded face photo + text description
Output: surface-level skin feature description (NO medical diagnosis)
"""

import base64
import traceback
from openai import OpenAI
from config import DASHSCOPE_API_KEY, DASHSCOPE_BASE_URL, QWEN_VL_MODEL, QWEN_TEXT_MODEL


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


async def analyze_skin(image_base64: str, user_text: str) -> dict:
    """
    Call Qwen-VL-Max (or Qwen text model if no image) to analyze the user's skin.
    Returns dict with:
    - error: bool
    - error_type: str (if error)
    - content: str (the analysis text or error message)
    """
    try:
        client = OpenAI(
            api_key=DASHSCOPE_API_KEY,
            base_url=DASHSCOPE_BASE_URL,
            timeout=60.0,
        )

        has_image = bool(image_base64)

        if has_image:
            # Multi-modal: image + text
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
            # Text-only: user didn't upload a photo
            user_content = (
                f"用户没有上传照片，只发来了以下文字描述：\n\n"
                f"\"{user_text}\"\n\n"
                f"请根据文字描述，直接给出皮肤分析和建议。"
                f"如果没有具体描述皮肤问题，请友好地提醒用户上传照片可以让你进行更准确的表面特征分析，"
                f"同时你也可以基于文字描述的皮肤困扰给一些初步的轻医美项目科普建议。"
            )
            model = QWEN_TEXT_MODEL

        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_content}
            ],
            stream=False,
            temperature=0.7,
            max_tokens=1024
        )

        content = response.choices[0].message.content
        return {"error": False, "content": content}

    except Exception as e:
        error_type = type(e).__name__
        traceback.print_exc()

        # Map known error types to user-friendly messages
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
