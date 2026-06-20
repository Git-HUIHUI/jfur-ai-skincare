# -*- coding: utf-8 -*-
"""
Test the actual generate_preview function from the agent
"""
import sys
sys.path.insert(0, "D:/medical-aesthetics-ai-agent/backend")

import asyncio
from agent.nodes.generate_preview import generate_preview
from agent.nodes.analyze import analyze_skin
from knowledge.projects import KNOWLEDGE

print("=== Test: generate_preview ===")
result = asyncio.run(generate_preview("淡化痘印，缩小毛孔，提亮肤色", n=1, size="1024*1024"))
print(f"success: {result['success']}")
if result['success']:
    print(f"image_urls: {len(result['image_urls'])} images")
    for u in result['image_urls']:
        print(f"  URL: {u[:120]}")
else:
    print(f"message: {result['message']}")

print("\n=== Test: analyze_skin (text-only) ===")
analysis = asyncio.run(analyze_skin("", "我脸上有痘印，T区毛孔粗大，肤色暗沉"))
print(f"Analysis length: {len(analysis)} chars")
print(f"Preview: {analysis[:300]}...")

print("\n=== Test: Knowledge base ===")
print(f"Projects: {len(KNOWLEDGE)}")
for p in KNOWLEDGE:
    print(f"  - {p['name']}: {p['price']}")
