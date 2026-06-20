# -*- coding: utf-8 -*-
"""Full pipeline test with a real PNG image"""
import httpx, json, asyncio, sys
sys.path.insert(0, "D:/medical-aesthetics-ai-agent/backend")

API_URL = "http://localhost:8001"

async def test_text_only():
    """Test 1: Text-only chat"""
    print("=" * 50)
    print("TEST 1: Text-only chat (qwen-max)")
    print("=" * 50)

    messages = [{"role": "user", "content": "我T区毛孔粗大，肤色暗沉，想了解适合什么项目"}]
    form_data = {"messages": json.dumps(messages)}

    async with httpx.AsyncClient(timeout=180.0) as client:
        async with client.stream("POST", f"{API_URL}/api/chat", data=form_data) as resp:
            print(f"Status: {resp.status_code}")
            events = []
            buffer = ""; current = ""
            async for chunk in resp.aiter_bytes():
                buffer += chunk.decode("utf-8")
                lines = buffer.split("\n"); buffer = lines.pop() or ""
                for line in lines:
                    if line.startswith("event: "): current = line[7:].strip()
                    elif line.startswith("data: "):
                        d = json.loads(line[6:])
                        dt = d.get("type","?")
                        step = d.get("step","?")
                        events.append(current)
                        if dt == "error": print(f"  ERROR: {d.get('content','')[:200]}")
                        elif dt == "followup": print(f"  [{current}] followup: {d.get('content','')[:100]}...")
                        elif dt in ("analysis","recommendation"): print(f"  [{current}] {dt}: step={step}")
                        else: print(f"  [{current}] {dt} step={step}")

            print(f"\nEvents: {len(events)} types={set(events)}")
            ok = "analysis" in events and "followup" in events
            print(f"RESULT: {'PASS' if ok else 'FAIL'}")
            return ok

async def test_with_image():
    """Test 2: Image upload chat"""
    print("\n" + "=" * 50)
    print("TEST 2: Image upload (qwen-vl-max)")
    print("=" * 50)

    # Read previously generated real PNG
    with open("D:/medical-aesthetics-ai-agent/backend/test_face.png", "rb") as f:
        img_bytes = f.read()
    print(f"Image: {len(img_bytes)} bytes")

    messages = [{"role": "user", "content": "请分析我照片上的皮肤状况，我担心痘印和肤色暗沉"}]
    files = {
        "messages": (None, json.dumps(messages)),
        "image": ("face.png", img_bytes, "image/png")
    }

    async with httpx.AsyncClient(timeout=300.0) as client:
        async with client.stream("POST", f"{API_URL}/api/chat", files=files) as resp:
            print(f"Status: {resp.status_code}")
            events = []
            buffer = ""; current = ""
            async for chunk in resp.aiter_bytes():
                buffer += chunk.decode("utf-8")
                lines = buffer.split("\n"); buffer = lines.pop() or ""
                for line in lines:
                    if line.startswith("event: "): current = line[7:].strip()
                    elif line.startswith("data: "):
                        d = json.loads(line[6:])
                        dt = d.get("type","?")
                        step = d.get("step","?")
                        events.append(current)
                        if dt == "error":
                            err = d.get("content","")[:300]
                            print(f"  [{current}] ERROR: {err}")
                        elif dt == "analysis":
                            print(f"  [{current}] analysis step={step} len={len(d.get('content',''))}")
                        elif dt == "followup":
                            print(f"  [{current}] followup: {d.get('content','')[:120]}...")
                        elif dt == "recommendation":
                            recs = d.get("recommendations",[])
                            names = [r.get("name","?") for r in recs]
                            print(f"  [{current}] recommendation: {names}")
                        elif dt == "preview":
                            urls = d.get("image_urls",[])
                            print(f"  [{current}] preview: {len(urls)} images")
                        elif dt == "booking":
                            print(f"  [{current}] booking: stores={len(d.get('stores',[]))}")
                        else:
                            print(f"  [{current}] {dt}: step={step}")

            print(f"\nEvents: {len(events)} types={set(events)}")
            has_analysis = "analysis" in events
            has_followup = "followup" in events
            has_recommendation = "recommendation" in events
            has_preview = "preview" in events
            has_booking = "booking" in events
            ok = has_analysis and has_followup  # at minimum these must pass
            print(f"Analysis:{has_analysis} Followup:{has_followup} Rec:{has_recommendation} Preview:{has_preview} Booking:{has_booking}")
            print(f"RESULT: {'PASS' if ok else 'FAIL'}")
            return ok

async def main():
    print("晶肤AI美肤助手 - Full Pipeline E2E Test\n")
    t1 = await test_text_only()
    t2 = await test_with_image()
    print("\n" + "=" * 50)
    all_ok = t1 and t2
    print(f"OVERALL: {'ALL TESTS PASSED' if all_ok else 'SOME TESTS FAILED'}")
    print("=" * 50)

asyncio.run(main())
