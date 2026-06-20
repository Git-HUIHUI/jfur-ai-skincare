import { Sparkles } from "lucide-react"

export function StatusBubble({ text }: { text: string }) {
  return (
    <div className="flex items-start gap-2.5">
      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#D4A853] to-[#2B5F8A] flex items-center justify-center flex-shrink-0 animate-pulse">
        <Sparkles className="w-4 h-4 text-white" />
      </div>
      <div className="bg-white/60 backdrop-blur rounded-full px-4 py-1.5 border border-gray-200">
        <p className="text-xs text-gray-500">{text}</p>
      </div>
    </div>
  )
}
