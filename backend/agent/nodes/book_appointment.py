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
    """
    Return store list and booking guidance.
    Demo: mock data; real booking through official website.
    Returns dict with:
    - stores: list of store dicts
    - message: str
    - error: bool
    - error_type: str (if error)
    """
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
