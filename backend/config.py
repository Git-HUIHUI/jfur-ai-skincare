import os
from dotenv import load_dotenv

load_dotenv()

DASHSCOPE_API_KEY = os.getenv("DASHSCOPE_API_KEY", "")
CHROMA_DB_PATH = os.getenv("CHROMA_DB_PATH", "./chroma_db")
DASHSCOPE_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
QWEN_VL_MODEL = "qwen-vl-max"
QWEN_TEXT_MODEL = "qwen-max"
BGE_MODEL = "BAAI/bge-small-zh-v1.5"

# 火山方舟 (Ark) — Seedream 4.5 图生图效果模拟
ARK_API_KEY = os.getenv("ARK_API_KEY", "")
ARK_BASE_URL = "https://ark.cn-beijing.volces.com/api/v3"
ARK_IMAGE_MODEL = "doubao-seedream-4-5-251128"

# Uploads 目录的公网地址（Seedream 需要 URL 访问图片）
# 开发环境用 localhost，部署时改为你的域名
UPLOADS_BASE_URL = os.getenv("UPLOADS_BASE_URL", "http://localhost:8001")
