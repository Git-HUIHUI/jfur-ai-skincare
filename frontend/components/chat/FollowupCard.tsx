import { useState } from "react"
import { Sparkles, Send } from "lucide-react"
import type { Message } from "@/lib/types"

export function FollowupCard({ message, onReply }: { message: Message; onReply: (text: string) => void }) {
  const [customReply, setCustomReply] = useState("")

  // Extract quick-reply options from the follow-up message
  // The LLM typically generates numbered options like "1. 是的，直接推荐\n2. 我想补充..."
  const rawLines = message.content
    .split(/\n/)
    .map((l) => l.trim())
    .filter(Boolean)
  const quickReplies: string[] = rawLines
    .filter((l) => /^\d+[\.\、\)]\s*/.test(l) || l.includes("？") || l.includes("?"))
    .map((l) => l.replace(/^\d+[\.\、\)]\s*/, ""))
    // Fallback: if parsing yields nothing, offer 3 generic choices
  if (quickReplies.length === 0) {
    quickReplies.push("是的，请直接推荐适合我的项目", "我还想补充一些信息", "先看看有哪些项目可以选择")
  }

  const handleQuickReply = (text: string) => {
    onReply(text)
  }

  const handleCustomReply = () => {
    if (!customReply.trim()) return
    onReply(customReply.trim())
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
          <p className="text-sm text-gray-700 leading-relaxed whitespace-pre-wrap">{message.content}</p>
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
