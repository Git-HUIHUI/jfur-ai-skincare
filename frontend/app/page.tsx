"use client"

import { useState, useRef, useEffect, useCallback } from "react"
import { Send, ImagePlus, X, Sparkles } from "lucide-react"
import Image from "next/image"
import type { Message } from "@/lib/types"
import { TopBar } from "@/components/chat/TopBar"
import { UserBubble } from "@/components/chat/UserBubble"
import { AnalysisCard } from "@/components/chat/AnalysisCard"
import { FollowupCard } from "@/components/chat/FollowupCard"
import { RecommendationCard } from "@/components/chat/RecommendationCard"
import { PreviewCard } from "@/components/chat/PreviewCard"
import { BookingCard } from "@/components/chat/BookingCard"
import { StatusBubble } from "@/components/chat/StatusBubble"
import { EmptyState } from "@/components/chat/EmptyState"
import { ErrorBoundary } from "@/components/ErrorBoundary"

const API_URL = process.env.NEXT_PUBLIC_API_URL || process.env.NEXT_PUBLIC_VERCEL_URL || ""

// ===== Main Page =====
export default function Home() {
  const [messages, setMessages] = useState<Message[]>([])
  const [inputText, setInputText] = useState("")
  const [uploadedImage, setUploadedImage] = useState<File | null>(null)
  const [imagePreview, setImagePreview] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [statusText, setStatusText] = useState("")
  const [threadId, setThreadId] = useState<string | null>(null)

  const messagesEndRef = useRef<HTMLDivElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const inputTextRef = useRef(inputText)
  inputTextRef.current = inputText  // Keep ref in sync for onReply closure

  // Auto-scroll
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [messages, statusText])

  // Handle image upload
  const handleImageUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      setUploadedImage(file)
      setImagePreview(URL.createObjectURL(file))
    }
  }

  const removeImage = () => {
    setUploadedImage(null)
    if (imagePreview) {
      URL.revokeObjectURL(imagePreview)
      setImagePreview(null)
    }
    // Reset file input so onChange fires for the same file next time
    if (fileInputRef.current) {
      fileInputRef.current.value = ""
    }
  }

  // Handle drag & drop
  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    const file = e.dataTransfer.files?.[0]
    if (file && file.type.startsWith("image/")) {
      setUploadedImage(file)
      setImagePreview(URL.createObjectURL(file))
    }
  }, [])

  // Process SSE events from backend
  const processSSE = async (response: Response) => {
    const reader = response.body?.getReader()
    if (!reader) return

    const decoder = new TextDecoder()
    let buffer = ""

    while (true) {
      const { done, value } = await reader.read()
      if (done) break

      buffer += decoder.decode(value, { stream: true })
      const lines = buffer.split("\n")
      buffer = lines.pop() || ""

      let currentEvent = ""

      for (const line of lines) {
        if (line.startsWith("event: ")) {
          currentEvent = line.slice(7).trim()
        } else if (line.startsWith("data: ")) {
          const data = JSON.parse(line.slice(6))

          // 安全地获取字符串内容，防止循环引用
          const getSafeString = (val: any): string => {
            if (typeof val === 'string') return val
            if (val === null || val === undefined) return ''
            try {
              const seen = new WeakSet()
              return JSON.stringify(val, (key, value) => {
                if (typeof value === 'object' && value !== null) {
                  if (seen.has(value)) return '[Circular]'
                  seen.add(value)
                }
                return value
              }, 2)
            } catch {
              return '[无法显示的内容]'
            }
          }

          switch (currentEvent) {
            case "status":
              setStatusText(getSafeString(data.content))
              break

            case "analysis":
              setStatusText("")
              setMessages(prev => [...prev, {
                id: crypto.randomUUID(),
                role: "ai",
                type: "analysis",
                content: getSafeString(data.content),
                disclaimer: data.disclaimer,
                step: data.step,
              }])
              break

            case "followup":
              setStatusText("")
              setThreadId(data.thread_id || null)
              setMessages(prev => [...prev, {
                id: crypto.randomUUID(),
                role: "ai",
                type: "followup",
                content: getSafeString(data.content),
                step: data.step,
              }])
              break

            case "recommendation":
              setStatusText("")
              setMessages(prev => [...prev, {
                id: crypto.randomUUID(),
                role: "ai",
                type: "recommendation",
                content: getSafeString(data.content),
                recommendations: data.recommendations || [],
                step: data.step,
              }])
              break

            case "review":
              setStatusText("")
              setMessages(prev => [...prev, {
                id: crypto.randomUUID(),
                role: "system",
                type: "text",
                content: getSafeString(data.content),
              }])
              break

            case "preview":
              setStatusText("")
              setMessages(prev => [...prev, {
                id: crypto.randomUUID(),
                role: "ai",
                type: "preview",
                content: getSafeString(data.content),
                image_urls: data.image_urls || [],
                disclaimer: data.disclaimer,
                step: data.step,
              }])
              break

            case "booking":
              setStatusText("")
              setMessages(prev => [...prev, {
                id: crypto.randomUUID(),
                role: "ai",
                type: "booking",
                content: getSafeString(data.content),
                stores: data.stores || [],
                step: data.step,
              }])
              break

            case "error":
              setStatusText("")
              setMessages(prev => [...prev, {
                id: crypto.randomUUID(),
                role: "system",
                type: "text",
                content: `❌ ${getSafeString(data.content)}`,
              }])
              break

            case "done":
              setStatusText("")
              setIsLoading(false)
              break
          }
        }
      }
    }
  }

  // Send message to backend
  const sendMessage = async (overrideText?: any) => {
    // 安全地确保 overrideText 是字符串
    const safeOverride = typeof overrideText === 'string' ? overrideText : undefined
    const textToSend = safeOverride || inputTextRef.current.trim()
    if (!textToSend && !uploadedImage) return
    if (isLoading) return

    const userMsg: Message = {
      id: crypto.randomUUID(),
      role: "user",
      type: "text",
      content: String(textToSend || "请帮我分析我的皮肤状况"),
      image_preview: imagePreview,
    }

    setMessages(prev => [...prev, userMsg])
    setInputText("")
    setIsLoading(true)
    setStatusText("🔍 正在处理您的请求...")

    // Build form data
    const formData = new FormData()
    const msgList = messages.concat(userMsg).map(m => ({
      role: m.role,
      content: m.content,
    }))
    formData.append("messages", JSON.stringify(msgList))

    if (uploadedImage) {
      formData.append("image", uploadedImage)
    }

    if (threadId) {
      formData.append("thread_id", threadId)
    }

    removeImage()

    try {
      const response = await fetch(`${API_URL}/api/chat`, {
        method: "POST",
        body: formData,
      })
      await processSSE(response)
    } catch (err) {
      setMessages(prev => [...prev, {
        id: crypto.randomUUID(),
        role: "system",
        type: "text",
        content: `❌ 网络错误：无法连接到后端服务。请确认后端已启动: ${API_URL}`,
      }])
      setIsLoading(false)
      setStatusText("")
    }
  }

  // Handle key press
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      sendMessage()
    }
  }

  // Render the correct bubble component for each message type
  const renderMessage = (msg: Message) => {
    switch (msg.type) {
      case "analysis":
        return <AnalysisCard message={msg} />
      case "followup":
        return <FollowupCard message={msg} onReply={(text) => {
          setInputText(text)
          setTimeout(() => sendMessage(text), 100)
        }} />
      case "recommendation":
        return <RecommendationCard message={msg} />
      case "preview":
        return <PreviewCard message={msg} />
      case "booking":
        return <BookingCard message={msg} />
      default:
        if (msg.role === "user") {
          return <UserBubble message={msg} />
        }
        return (
          <div className="flex items-start gap-2.5">
            <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#D4A853] to-[#2B5F8A] flex items-center justify-center flex-shrink-0">
              <Sparkles className="w-4 h-4 text-white" />
            </div>
            <div className="max-w-[82%] bg-white rounded-2xl rounded-tl-sm shadow-sm border border-gray-100 px-4 py-2.5">
              <p className="text-sm text-gray-700 leading-relaxed">{msg.content}</p>
            </div>
          </div>
        )
    }
  }

  return (
    <ErrorBoundary>
      <div className="flex flex-col h-screen max-w-3xl mx-auto">
        <TopBar />

        {/* Messages area */}
        <main className="flex-1 overflow-y-auto custom-scrollbar pt-16 pb-24 px-4">
          {messages.length === 0 && !isLoading && <EmptyState onHintClick={(text) => setInputText(text)} />}
          <div className="space-y-4">
            {messages.map(msg => (
              <div key={msg.id}>{renderMessage(msg)}</div>
            ))}
            {statusText && <StatusBubble text={statusText} />}
          </div>
          <div ref={messagesEndRef} />
        </main>

        {/* Input area */}
        <footer className="fixed bottom-0 left-0 right-0 bg-white/80 backdrop-blur-md border-t border-gray-200">
          <div className="max-w-3xl mx-auto px-4 py-3">
            {/* Image preview thumbnail */}
            {imagePreview && (
              <div className="mb-2 inline-block relative">
                <div className="w-16 h-16 rounded-lg overflow-hidden border border-gray-200">
                  <Image src={imagePreview} alt="预览" width={64} height={64} className="w-full h-full object-cover" />
                </div>
                <button
                  onClick={removeImage}
                  className="absolute -top-1.5 -right-1.5 w-5 h-5 bg-red-500 text-white rounded-full flex items-center justify-center shadow-sm hover:bg-red-600"
                >
                  <X className="w-3 h-3" />
                </button>
              </div>
            )}

            <div
              className="flex items-end gap-2"
              onDrop={handleDrop}
              onDragOver={(e) => e.preventDefault()}
            >
              {/* Image upload button */}
              <button
                onClick={() => fileInputRef.current?.click()}
                className="flex-shrink-0 w-10 h-10 rounded-full border border-gray-300 flex items-center justify-center text-gray-400 hover:text-[#2B5F8A] hover:border-[#2B5F8A] transition-colors"
                title="上传照片"
              >
                <ImagePlus className="w-5 h-5" />
              </button>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                onChange={handleImageUpload}
                className="hidden"
              />

              {/* Text input */}
              <div className="flex-1 relative">
                <input
                  ref={inputRef}
                  type="text"
                  value={inputText}
                  onChange={(e) => setInputText(e.target.value)}
                  onKeyDown={handleKeyDown}
                  placeholder="输入你的皮肤问题..."
                  className="w-full px-4 py-2.5 pr-12 bg-gray-50 border border-gray-200 rounded-2xl text-sm focus:outline-none focus:border-[#2B5F8A] focus:ring-2 focus:ring-[#2B5F8A]/10 transition-all"
                  disabled={isLoading}
                />
              </div>

              {/* Send button */}
              <button
                onClick={sendMessage}
                disabled={isLoading || (!inputText.trim() && !uploadedImage)}
                className="flex-shrink-0 w-10 h-10 rounded-full bg-[#2B5F8A] text-white flex items-center justify-center hover:bg-[#1A3A56] transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
              >
                <Send className="w-5 h-5" />
              </button>
            </div>

            <p className="text-center text-xs text-gray-400 mt-2">
              ⚠️ AI分析仅作参考，不能替代专业医生面诊
            </p>
          </div>
        </footer>
      </div>
    </ErrorBoundary>
  )
}
