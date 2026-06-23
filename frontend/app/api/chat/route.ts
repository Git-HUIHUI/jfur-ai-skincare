// Next.js API route — proxies chat requests to backend
import { NextRequest } from 'next/server'

export async function POST(request: NextRequest) {
  // 仅服务端读取：代理到本机 FastAPI，公网用户经 ngrok → Next.js → localhost:8001
  const BACKEND_URL = process.env.BACKEND_URL || process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8001'

  try {
    const formData = await request.formData()
    const response = await fetch(`${BACKEND_URL}/api/chat`, {
      method: 'POST',
      body: formData,
    })

    return new Response(response.body, {
      status: response.status,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      },
    })
  } catch (error) {
    return new Response(
      JSON.stringify({ error: 'Failed to connect to backend' }),
      { status: 502, headers: { 'Content-Type': 'application/json' } }
    )
  }
}
