import os
import sys
from dotenv import load_dotenv

load_dotenv()


def validate_env() -> bool:
    """
    验证必需的环境变量是否已配置
    返回: 是否所有必需变量都已配置
    """
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

# ========== 火山方舟 (Ark) — Seedream 4.5 图生图效果模拟 ==========
ARK_API_KEY = os.getenv("ARK_API_KEY", "")
ARK_BASE_URL = "https://ark.cn-beijing.volces.com/api/v3"
ARK_IMAGE_MODEL = "doubao-seedream-4-5-251128"

# ========== 服务配置 ==========
# Uploads 目录的公网地址（Seedream 需要 URL 访问图片）
# 开发环境用 localhost，部署时改为你的域名
UPLOADS_BASE_URL = os.getenv("UPLOADS_BASE_URL", "http://localhost:8001")

# ========== 图片上传限制 ==========
MAX_IMAGE_SIZE_MB = 10  # 最大 10MB
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp"}

# ========== API 配置 ==========
API_RETRY_TIMES = 2  # 重试次数
API_RETRY_DELAY = 1.0  # 重试间隔（秒）

# ========== CORS 配置 ==========
# 允许的来源，多个用逗号分隔
# 开发环境: http://localhost:3000,http://localhost:3001
# 生产环境: https://yourdomain.com
CORS_ALLOWED_ORIGINS = os.getenv("CORS_ALLOWED_ORIGINS", "*")
