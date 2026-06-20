"""
Node 4 — Effect Preview Generation (generate_preview)
Input: user's original photo (base64 data URI or URL) + improvement prompts
Output: AI-generated simulated effect image via 火山方舟 Seedream 4.5 (图生图)
"""

import os
import uuid
import aiohttp
from config import ARK_API_KEY, ARK_BASE_URL, ARK_IMAGE_MODEL


PREVIEW_PROMPT_TEMPLATE = (
    "保持人物面部特征和五官完全不变，仅对皮肤做以下改善：{improvements}。"
    "自然效果，不要变形，不要换脸，不要改变发型、服装、背景。"
    "高清写实摄影风格，冷白皮质感"
)

SEEDREAM_ENDPOINT = f"{ARK_BASE_URL}/images/generations"


async def generate_preview(
    improvements: str,
    image_url: str = "",
    n: int = 1,
    size: str = "2K",
) -> dict:
    """
    Generate a simulated post-treatment effect image using Seedream 4.5.
    Accepts either a public URL or a data URI (data:image/jpeg;base64,...).
    If image_url is empty, skips generation gracefully.
    """
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
                    urls = [img["url"] for img in data.get("data", [])]
                    return {
                        "success": True,
                        "image_urls": urls,
                        "message": "效果模拟图已生成（基于您的照片，Seedream 4.5）",
                        "error": False,
                    }
                else:
                    body = await response.text()
                    return {
                        "success": False,
                        "image_urls": [],
                        "message": f"效果图生成失败（{_http_status_text(response.status)}）。模拟效果请以医生面诊为准。",
                        "error": True,
                        "error_type": f"generate_preview/HTTP_{response.status}",
                    }

    except Exception as e:
        import traceback
        traceback.print_exc()

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
