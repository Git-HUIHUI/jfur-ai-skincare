from pyngrok import ngrok
import time

# 启动 ngrok 隧道
print("正在启动 ngrok 隧道...")
tunnel = ngrok.connect(3000, "http")
public_url = tunnel.public_url
print("=" * 60)
print(f"✅ 公网地址已获取: {public_url}")
print("=" * 60)
print("")
print("🔗 公网访问地址:")
print(f"   {public_url}")
print("")
print("💡 提示:")
print("   - 保持此窗口打开，隧道将持续运行")
print("   - 本机需同时运行：后端(8001) + 前端(3000)，公网用户经 Next.js 代理访问后端")
print("   - 不要在前端 .env.local 设置 NEXT_PUBLIC_API_URL=localhost:8001")
print("   - 如需停止，按 Ctrl+C")
print("")

# 保持脚本运行
try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    print("\n正在关闭隧道...")
    ngrok.disconnect(public_url)
    print("隧道已关闭。")
