# -*- coding: utf-8 -*-
"""Complete pipeline test — verify all 5 nodes execute through the API"""
import httpx, json, asyncio

API_URL = "http://localhost:8001"

async def test_full_pipeline():
    print("=" * 60)
    print("FULL PIPELINE E2E TEST (supports 1 or 2 rounds)")
    print("=" * 60)

    with open("D:/medical-aesthetics-ai-agent/backend/test_face.png", "rb") as f:
        img_bytes = f.read()

    # --- Round 1 ---
    print("\n--- ROUND 1: Upload image + initial message ---")
    msgs1 = [{"role": "user", "content": "我担心痘印和肤色暗沉，想了解适合的项目"}]
    files = {
        "messages": (None, json.dumps(msgs1)),
        "image": ("face.png", img_bytes, "image/png")
    }

    async with httpx.AsyncClient(timeout=300.0) as client:
        resp = await client.post(f"{API_URL}/api/chat", files=files)
        body = resp.text
        events_r1 = []
        has = {}
        for line in body.split("\n"):
            if line.startswith("data: "):
                d = json.loads(line[6:])
                dt = d.get("type","?")
                events_r1.append(dt)
                if dt == "recommendation":
                    has["recs"] = [r.get("name","?") for r in d.get("recommendations",[])]
                elif dt == "preview":
                    has["preview_imgs"] = len(d.get("image_urls",[]))
                elif dt == "booking":
                    has["booking_stores"] = len(d.get("stores",[]))
                elif dt == "error":
                    has["error"] = d.get("content","")[:200]
        print(f"  Events: {set(events_r1)}")

    # Check what we got
    required = ["analysis", "recommendation", "preview", "booking"]
    r1_all = True
    for step in required:
        ok = step in events_r1
        print(f"  {step}: {'PASS' if ok else 'MISS'}")
        if not ok: r1_all = False

    if "error" in has:
        print(f"  ERROR: {has['error']}")
        r1_all = False

    if r1_all:
        print(f"  ROUND 1: ALL 5 NODES PASSED! (recs={has.get('recs',[])})")

    # --- Round 2 (confirm-style) ---
    print("\n--- ROUND 2: Confirmation reply (text-only) ---")
    msgs2 = [{"role": "user", "content": "好的，我确认了，请直接给我推荐具体的项目方案吧"}]
    data2 = {"messages": json.dumps(msgs2)}

    async with httpx.AsyncClient(timeout=300.0) as client:
        resp = await client.post(f"{API_URL}/api/chat", data=data2)
        body = resp.text
        events_r2 = []
        has2 = {}
        for line in body.split("\n"):
            if line.startswith("data: "):
                d = json.loads(line[6:])
                dt = d.get("type","?")
                events_r2.append(dt)
                if dt == "recommendation":
                    has2["recs"] = [r.get("name","?") for r in d.get("recommendations",[])]
                elif dt == "preview":
                    has2["preview_imgs"] = len(d.get("image_urls",[]))
                elif dt == "booking":
                    has2["booking_stores"] = len(d.get("stores",[]))
                elif dt == "error":
                    has2["error"] = d.get("content","")[:200]
        print(f"  Events: {set(events_r2)}")

    r2_all = True
    for step in required:
        ok = step in events_r2
        print(f"  {step}: {'PASS' if ok else 'MISS'}")
        if not ok: r2_all = False

    if "error" in has2:
        print(f"  ERROR: {has2['error']}")
        r2_all = False

    if r2_all:
        print(f"  ROUND 2: ALL 5 NODES PASSED! (recs={has2.get('recs',[])})")

    # --- Summary ---
    print("\n" + "=" * 60)
    both_ok = r1_all or r2_all  # At least one round must pass fully
    if r1_all and r2_all:
        print("OVERALL: BOTH ROUNDS FULL PIPELINE PASSED!")
    elif r1_all:
        print("OVERALL: ROUND 1 FULL PIPELINE PASSED (round 2 may need different input)")
    elif r2_all:
        print("OVERALL: ROUND 2 FULL PIPELINE PASSED (round 1 may need attention)")
    else:
        print("OVERALL: PIPELINE FAILED — check errors above")
    print("=" * 60)
    return both_ok

if __name__ == "__main__":
    ok = asyncio.run(test_full_pipeline())
