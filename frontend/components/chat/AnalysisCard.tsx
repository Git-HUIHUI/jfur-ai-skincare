"use client"

import { useState, useEffect } from "react"
import { Sparkles } from "lucide-react"
import type { Message } from "@/lib/types"

export function AnalysisCard({ message }: { message: Message }) {
  const [displayText, setDisplayText] = useState("")
  const [isTyping, setIsTyping] = useState(true)

  useEffect(() => {
    const text = message.content
    let i = 0
    setDisplayText("")
    const timer = setInterval(() => {
      if (i < text.length) {
        setDisplayText(text.slice(0, i + 1))
        i++
      } else {
        setIsTyping(false)
        clearInterval(timer)
      }
    }, 20)
    return () => clearInterval(timer)
  }, [message.content])

  return (
    <div className="flex items-start gap-2.5">
      {/* AI avatar */}
      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#D4A853] to-[#2B5F8A] flex items-center justify-center flex-shrink-0">
        <Sparkles className="w-4 h-4 text-white" />
      </div>
      <div className="max-w-[82%] bg-white rounded-2xl rounded-tl-sm shadow-sm border border-gray-100 overflow-hidden">
        <div className="px-4 py-1.5 bg-gradient-to-r from-[#F7F3EB] to-white border-b border-gray-50">
          <span className="text-xs font-medium text-[#2B5F8A]">🔍 皮肤分析结果</span>
        </div>
        <div className="px-4 py-3">
          <p className={`text-sm text-gray-700 leading-relaxed whitespace-pre-wrap ${isTyping ? "typing-cursor" : ""}`}>
            {displayText}
          </p>
        </div>
        {message.disclaimer && !isTyping && (
          <div className="px-4 py-2 bg-amber-50/50 border-t border-amber-100">
            <p className="text-xs text-amber-700">{message.disclaimer}</p>
          </div>
        )}
      </div>
    </div>
  )
}
