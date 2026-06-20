# -*- coding: utf-8 -*-
"""Complete pipeline test: two-round conversation via API"""
import httpx, json, asyncio

API_URL = "http://localhost:8001"

async def test_two_round_pipeline():
    print("=" * 60)
    print("TWO-ROUND FULL PIPELINE TEST (via API)")
    print("=" * 60)

    # Round 1: Upload image + initial question
    print("\n--- ROUND 1: First message (with image) ---")
    with open("D:/medical-aesthetics-ai-agent/backend/test_face.png", "rb") as f:
        img_bytes = f.read()

    msgs1 = [{"role": "user", "content": "我担心痘印和肤色暗沉，想了解适合的项目"}]
    files = {
        "messages": (None, json.dumps(msgs1)),
        "image": ("face.png", img_bytes, "image/png")
    }

    async with httpx.AsyncClient(timeout=300.0) as client:
        resp = await client.post(f"{API_URL}/api/chat", files=files)
        body = resp.text
        events_r1 = []
        for line in body.split("\n"):
            if line.startswith("data: "):
                d = json.loads(line[6:])
                events_r1.append(d.get("type","?"))
        print(f"  Round 1 events: {set(events_r1)}")
        assert "analysis" in events_r1, "Round 1: no analysis!"
        assert "followup" in events_r1, "Round 1: no followup!"
        assert "done" in events_r1, "Round 1: no done!"
        print("  Round 1 PASSED (analysis + followup)")

    # Round 2: Confirm and get recommendations
    print("\n--- ROUND 2: Confirmation reply ---")
    msgs2 = [{"role": "user", "content": "好的，我确认了，请直接给我推荐具体的项目方案吧"}]
    data2 = {"messages": json.dumps(msgs2)}

    async with httpx.AsyncClient(timeout=300.0) as client:
        resp = await client.post(f"{API_URL}/api/chat", data=data2)
        body = resp.text
        events_r2 = []
        recs_found = []
        preview_found = False
        booking_found = False
        errors = []

        for line in body.split("\n"):
            if line.startswith("data: "):
                d = json.loads(line[6:])
                dt = d.get("type","?")
                events_r2.append(dt)
                if dt == "recommendation":
                    recs_found = [r.get("name","?") for r in d.get("recommendations",[])]
                    print(f"  [OK] recommendation: {recs_found}")
                elif dt == "preview":
                    preview_found = True
                    n = len(d.get("image_urls",[]))
                    print(f"  [OK] preview: {n} images")
                elif dt == "booking":
                    booking_found = True
                    print(f"  [OK] booking")
                elif dt == "error":
                    errors.append(d.get("content","")[:200])
                    print(f"  [ERR] {d.get('content','')[:200]}")
                elif dt in ("analysis","followup","review","status"):
                    pass  # normal

        print(f"  Round 2 events: {set(events_r2)}")

        # Verify
        checks = {
            "recommendation": "recommendation" in events_r2,
            "preview": preview_found,
            "booking": booking_found,
        }
        all_ok = True
        for step, ok in checks.items():
            s = "PASS" if ok else "FAIL"
            if not ok: all_ok = False
            print(f"  {step}: {s}")
        if errors:
            print(f"  errors: {errors}")
            all_ok = False

        print(f"\n  Recommendations: {recs_found}")
        if all_ok:
            print("  ROUND 2: FULL PIPELINE PASSED!")
        else:
            print("  ROUND 2: SOME STEPS FAILED")
        return all_ok, recs_found


if __name__ == "__main__":
    ok, recs = asyncio.run(test_two_round_pipeline())
    print("\n" + "=" * 60)
    print(f"OVERALL: {'ALL PASSED' if ok else 'SOME FAILED'}")
    print("=" * 60)
