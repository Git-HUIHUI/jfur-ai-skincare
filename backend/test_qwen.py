# -*- coding: utf-8 -*-
"""
Qwen-VL-Max 验证脚本 — 测试 DashScope 兼容 OpenAI API
"""
import sys
sys.path.insert(0, "D:/medical-aesthetics-ai-agent/backend")

from config import DASHSCOPE_API_KEY, DASHSCOPE_BASE_URL, QWEN_VL_MODEL
from openai import OpenAI

print("=== Qwen-VL-Max API Test ===")
print(f"Base URL: {DASHSCOPE_BASE_URL}")
print(f"Model: {QWEN_VL_MODEL}")

client = OpenAI(
    api_key=DASHSCOPE_API_KEY,
    base_url=DASHSCOPE_BASE_URL,
)

# Test 1: Text-only call (qwen-max for text)
print("\n--- Test 1: Text-only (qwen-max) ---")
try:
    response = client.chat.completions.create(
        model="qwen-max",
        messages=[
            {"role": "user", "content": "Hello, say 'API test passed' in one sentence."}
        ],
        max_tokens=50
    )
    print(f"Response: {response.choices[0].message.content}")
    print("SUCCESS!")
except Exception as e:
    print(f"FAILED: {e}")

# Test 2: Check available models
print("\n--- Test 2: List models ---")
try:
    models = client.models.list()
    model_ids = [m.id for m in models.data]
    print(f"Available models ({len(model_ids)}): {model_ids[:10]}...")
    # Check for vision-capable models
    vl_models = [m for m in model_ids if 'vl' in m.lower()]
    print(f"Vision models: {vl_models}")
except Exception as e:
    print(f"FAILED: {e}")

# Test 3: Image analysis via OpenAI-compatible API
print("\n--- Test 3: Vision analysis ---")
try:
    response = client.chat.completions.create(
        model=QWEN_VL_MODEL,  # qwen-vl-max
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": "Describe what you might see in a typical facial skin photo. Just give a brief generic response."
                    }
                ]
            }
        ],
        max_tokens=200
    )
    print(f"Response: {response.choices[0].message.content[:200]}")
    print("SUCCESS!")
except Exception as e:
    print(f"FAILED: {e}")
    print(f"  Type: {type(e).__name__}")
