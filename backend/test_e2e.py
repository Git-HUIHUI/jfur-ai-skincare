# -*- coding: utf-8 -*-
"""
End-to-end full pipeline test for 晶肤AI美肤助手
Tests: Chat API with text-only → SSE events → analyze → followup → match → preview → booking
"""
import httpx
import json
import asyncio

API_URL = "http://localhost:8001"

async def test_chat_text_only():
    """Test 1: Text-only chat (no image) — should work with qwen-max fallback"""
    print("=" * 60)
    print("TEST 1: Text-only chat (no image)")
    print("=" * 60)

    messages = [
        {"role": "user", "content": "我脸上有痘印，T区毛孔粗大，肤色暗沉，想了解一下适合什么项目"}
    ]
    form_data = {
        "messages": json.dumps(messages),
    }

    async with httpx.AsyncClient(timeout=120.0) as client:
        async with client.stream(
            "POST",
            f"{API_URL}/api/chat",
            data=form_data
        ) as response:
            print(f"Status: {response.status_code}")
            events = []
            buffer = ""
            current_event = ""

            async for chunk in response.aiter_bytes():
                buffer += chunk.decode("utf-8")
                lines = buffer.split("\n")
                buffer = lines.pop() or ""

                for line in lines:
                    if line.startswith("event: "):
                        current_event = line[7:].strip()
                    elif line.startswith("data: "):
                        data = json.loads(line[6:])
                        event_type = data.get("type", "unknown")
                        step = data.get("step", "")
                        content = str(data.get("content", ""))[:80]
                        events.append(current_event)
                        print(f"  [{current_event}] type={event_type}, step={step}, content={content}")

            # Print summary
            event_types = set(events)
            print(f"\nSummary: {len(events)} events, types: {event_types}")
            return events


async def test_chat_with_image():
    """Test 2: Chat with image upload — full multi-modal pipeline"""
    print("\n" + "=" * 60)
    print("TEST 2: Chat with image upload")
    print("=" * 60)

    # Create a tiny 1x1 JPEG for testing
    import base64
    # Minimal valid JPEG (1x1 pixel)
    tiny_jpeg = base64.b64decode(
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0a"
        "HBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIy"
        "MjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIA"
        "AhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQA"
        "AAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3"
        "ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWm"
        "p6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEA"
        "AwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSEx"
        "BhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYI1Jic4GRomJygpKjU2Nzg5OkNERU"
        "ZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsr"
        "O0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPw"
        "D3+iiigD//2Q=="
    )

    messages = [
        {"role": "user", "content": "请帮我分析我的皮肤状况，我主要担心痘印和肤色暗沉"}
    ]

    # Build multipart form data
    import io
    files = {
        "messages": (None, json.dumps(messages)),
        "image": ("test_face.jpg", io.BytesIO(tiny_jpeg), "image/jpeg")
    }

    async with httpx.AsyncClient(timeout=180.0) as client:
        async with client.stream(
            "POST",
            f"{API_URL}/api/chat",
            files=files
        ) as response:
            print(f"Status: {response.status_code}")
            events = []
            buffer = ""
            current_event = ""
            image_urls_found = []

            async for chunk in response.aiter_bytes():
                buffer += chunk.decode("utf-8")
                lines = buffer.split("\n")
                buffer = lines.pop() or ""

                for line in lines:
                    if line.startswith("event: "):
                        current_event = line[7:].strip()
                    elif line.startswith("data: "):
                        data = json.loads(line[6:])
                        event_type = data.get("type", "unknown")
                        step = data.get("step", "")
                        content = str(data.get("content", ""))[:100]
                        events.append(current_event)

                        if event_type == "preview":
                            urls = data.get("image_urls", [])
                            image_urls_found = urls
                            print(f"  [{current_event}] type={event_type}, step={step}, images={len(urls)}")
                        elif event_type == "recommendation":
                            recs = data.get("recommendations", [])
                            names = [r.get("name", "?") for r in recs]
                            print(f"  [{current_event}] type={event_type}, recommendations={names}")
                        elif event_type == "booking":
                            stores = data.get("stores", [])
                            store_names = [s.get("name", "?") for s in stores]
                            print(f"  [{current_event}] type={event_type}, stores={store_names}")
                        elif event_type == "analysis":
                            print(f"  [{current_event}] type={event_type}, step={step}, content={content}")
                        elif event_type == "followup":
                            print(f"  [{current_event}] type={event_type}, confirmed info")
                        else:
                            print(f"  [{current_event}] type={event_type}, step={step}")

            event_types = set(events)
            print(f"\nSummary: {len(events)} events, types: {event_types}")
            print(f"Images generated: {len(image_urls_found)}")

            # Verify pipeline completeness
            required_events = {"analysis", "followup", "recommendation", "preview", "booking"}
            found_events = {e for e in events if e in required_events or e == "status" or e == "review"}

            if "analysis" in events and "recommendation" in events:
                print("\nPIPELINE: analyze -> recommendation PASSED")
            if image_urls_found:
                print("PIPELINE: preview generation PASSED")
            if "booking" in events:
                print("PIPELINE: booking PASSED")

            return events, image_urls_found


if __name__ == "__main__":
    print("晶肤AI美肤助手 - End-to-End Test")
    print(f"Backend: {API_URL}")
    print()

    # Run tests
    events1 = asyncio.run(test_chat_text_only())
    events2, images = asyncio.run(test_chat_with_image())

    print("\n" + "=" * 60)
    print("ALL TESTS COMPLETE")
    print("=" * 60)
