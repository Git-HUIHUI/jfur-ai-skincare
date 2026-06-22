import { useState } from "react"
import { Sparkles, Send } from "lucide-react"
import type { Message } from "@/lib/types"

export function FollowupCard({ message, onReply }: { message: Message; onReply: (text: string) => void }) {
  const [customReply, setCustomReply] = useState("")

  // 安全处理内容 - 防止循环引用
  const safeContent = (() => {
    if (typeof message.content === 'string') return message.content
    try {
      const seen = new WeakSet()
      return JSON.stringify(message.content, (key, value) => {
        if (typeof value === 'object' && value !== null) {
          if (seen.has(value)) return '[Circular]'
          seen.add(value)
        }
        return value
      }, 2)
    } catch {
      return '[无法显示的内容]'
    }
  })()

  // Extract quick-reply options from the follow-up message
  // The LLM typically generates numbered options like "1. 是的，直接推荐\n2. 我想补充..."
  const rawLines = safeContent
    .split(/\n/)
    .map((l) => l.trim())
    .filter(Boolean)
  // 【修复】只匹配明确的数字选项，不匹配问题句，避免把追问问题当成快速回复
  const quickReplies: string[] = rawLines
    .filter((l) => /^\d+[\.\、\)]\s*/.test(l)) // 只匹配 "1. xxx" 这种格式
    .map((l) => l.replace(/^\d+[\.\、\)]\s*/, ""))
    // Fallback: 如果没有解析到明确的数字选项，直接提供三个通用选择（不显示问题）
  quickReplies.length === 0 ? quickReplies.push("是的，请直接推荐适合我的项目", "我还想补充一些信息", "先看看有哪些项目可以选择") : undefined

  const handleQuickReply = (text: string) => {
    // 确保只传递字符串
    onReply(String(text))
  }

  const handleCustomReply = (e?: React.MouseEvent | React.KeyboardEvent) => {
    // 防止事件对象干扰
    if (e) e.preventDefault()
    if (!customReply.trim()) return
    onReply(String(customReply.trim()))
    setCustomReply("")
  }

  return (
    <div className="flex items-start gap-2.5">
      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#D4A853] to-[#2B5F8A] flex items-center justify-center flex-shrink-0">
        <Sparkles className="w-4 h-4 text-white" />
      </div>
      <div className="max-w-[82%] bg-white rounded-2xl rounded-tl-sm shadow-sm border border-gray-100">
        <div className="px-4 py-1.5 bg-gradient-to-r from-[#F0F7FF] to-white border-b border-gray-50">
          <span className="text-xs font-medium text-[#2B5F8A]">💬 追问确认</span>
        </div>
        <div className="px-4 py-3">
          <p className="text-sm text-gray-700 leading-relaxed whitespace-pre-wrap">{safeContent}</p>
        </div>
        {/* Quick reply buttons */}
        <div className="px-4 pb-2 flex flex-wrap gap-1.5">
          {quickReplies.map((reply, i) => (
            <button
              key={i}
              onClick={() => handleQuickReply(reply)}
              className="text-xs px-3 py-1.5 bg-[#F0F7FF] border border-[#2B5F8A]/20 rounded-full text-[#2B5F8A] hover:bg-[#2B5F8A] hover:text-white transition-colors"
            >
              {reply}
            </button>
          ))}
        </div>
        {/* Custom reply input */}
        <div className="px-4 pb-3 flex items-center gap-2">
          <input
            type="text"
            value={customReply}
            onChange={(e) => setCustomReply(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter") handleCustomReply() }}
            placeholder="或输入你的回复..."
            className="flex-1 text-xs px-3 py-1.5 bg-gray-50 border border-gray-200 rounded-full focus:outline-none focus:border-[#2B5F8A] transition-colors"
          />
          <button
            onClick={handleCustomReply}
            disabled={!customReply.trim()}
            className="w-7 h-7 rounded-full bg-[#2B5F8A] text-white flex items-center justify-center hover:bg-[#1A3A56] transition-colors disabled:opacity-40"
          >
            <Send className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>
    </div>
  )
}
