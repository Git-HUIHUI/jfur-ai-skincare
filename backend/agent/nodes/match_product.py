"""
Node 3 — Product Matching (match_product)
Input: user's confirmed needs
Output: top matching Crystal Dermatology projects with descriptions and pricing
"""

import traceback
from rag.chroma_store import search_similar
from knowledge.projects import KNOWLEDGE


async def match_product(user_needs: str) -> dict:
    """
    Search ChromaDB for the best matching projects.
    Returns dict with:
    - recommendations: list of matched project dicts
    - message: str (recommendation message)
    - error: bool
    - error_type: str (if error)
    """
    try:
        matches = search_similar(user_needs, top_k=2)

        if not matches:
            return {
                "recommendations": KNOWLEDGE[:2],  # fallback: return first 2
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
            "recommendations": KNOWLEDGE[:2],  # Graceful fallback
            "message": f"智能匹配暂时遇到问题，以下是根据常见需求为您推荐的项目：",
            "error": True,
            "error_type": f"match_product/{error_type}",
        }
