# -*- coding: utf-8 -*-
"""完整链路测试 v3 — 模拟两次对话,走完 analyze→followup→match→preview→booking"""
import httpx, json, asyncio

API_URL = "http://localhost:8001"

async def test_full_pipeline():
    """两轮对话: (1)上传图片+文字 (2)确认回复 → 全链路"""
    with open("D:/medical-aesthetics-ai-agent/backend/test_face.png", "rb") as f:
        img_bytes = f.read()

    print("=" * 60)
    print("ROUND 1: Upload image + initial message")
    print("=" * 60)

    messages = [{"role": "user", "content": "请分析我的皮肤状况，我主要担心痘印和肤色暗沉"}]
    files = {"messages": (None, json.dumps(messages)), "image": ("face.png", img_bytes, "image/png")}

    client = httpx.Client(timeout=300.0)
    # Use sync client for simpler code
    resp = client.post(f"{API_URL}/api/chat", files=files)
    buffer = ""; current = ""
    analysis_ok = followup_ok = False
    thread_id = None

    for chunk in resp.iter_bytes():
        buffer += chunk.decode("utf-8")
        lines = buffer.split("\n"); buffer = lines.pop() or ""
        for line in lines:
            if line.startswith("event: "): current = line[7:].strip()
            elif line.startswith("data: "):
                d = json.loads(line[6:]); dt = d.get("type","?")
                if dt == "analysis": analysis_ok = True; print(f"  [OK] analysis: {len(d.get('content',''))} chars")
                elif dt == "followup": followup_ok = True; print(f"  [OK] followup generated")
                elif dt == "done":
                    tid = d.get("thread_id")
                    if tid: thread_id = tid
                    print(f"  [done] thread_id={thread_id}")
                elif dt == "error": print(f"  [ERR] {d.get('content','')[:200]}")
    resp.close()

    assert analysis_ok and followup_ok, "Round 1 incomplete!"
    print("Round 1 PASSED\n")

    # Round 2: confirm and proceed
    print("=" * 60)
    print("ROUND 2: Confirm need → full pipeline")
    print("=" * 60)

    messages2 = [
        {"role": "user", "content": "你刚才推荐的方案请给我详细介绍一下，确认我想了解，请继续推荐具体的项目"},
    ]
    files2 = {"messages": (None, json.dumps(messages2)), "image": ("", b"")}
    # Remove empty image field — send text-only continuation
    resp2 = client.post(f"{API_URL}/api/chat", data={"messages": json.dumps(messages2)})

    buffer = ""; current = ""
    results = {"analysis": False, "followup": False, "recommendation": False,
               "review": False, "preview": False, "booking": False}
    errors = []
    rec_names = []

    for chunk in resp2.iter_bytes():
        buffer += chunk.decode("utf-8")
        lines = buffer.split("\n"); buffer = lines.pop() or ""
        for line in lines:
            if line.startswith("event: "): current = line[7:].strip()
            elif line.startswith("data: "):
                d = json.loads(line[6:]); dt = d.get("type","?")
                if dt == "error": errors.append(d.get("content","")[:200])
                elif dt in results: results[dt] = True
                if dt == "recommendation":
                    rec_names = [r.get("name","?") for r in d.get("recommendations",[])]
                    print(f"  [OK] recommendation: {rec_names}")
                elif dt == "preview":
                    print(f"  [OK] preview: {len(d.get('image_urls',[]))} images")
                elif dt == "booking":
                    print(f"  [OK] booking: {len(d.get('stores',[]))} stores")
                elif dt == "analysis": print(f"  [OK] analysis (confirm response)")
                elif dt == "followup": print(f"  [OK] followup (confirmation)")
                elif dt == "review": print(f"  [OK] human review checkpoint")
    resp2.close()

    if errors:
        print(f"\n  Errors: {errors}")

    # Check results
    all_ok = True
    for step, passed in results.items():
        status = "PASS" if passed else "MISS"
        if not passed: all_ok = False
        print(f"  {step}: {status}")
    print(f"\nRecommendations: {rec_names}")
    print(f"Errors: {len(errors)}")

    if all_ok:
        print("FULL PIPELINE: ALL STEPS PASSED!")
    else:
        missing = [k for k, v in results.items() if not v]
        print(f"FULL PIPELINE: MISSING STEPS: {missing}")
        if errors:
            print(f"FIRST ERROR: {errors[0]}")

    client.close()
    return all_ok, results, errors


if __name__ == "__main__":
    ok, results, errors = asyncio.run(test_full_pipeline())
