import { Sparkles } from "lucide-react"
import type { Message } from "@/lib/types"

export function RecommendationCard({ message }: { message: Message }) {
  return (
    <div className="flex items-start gap-2.5">
      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#D4A853] to-[#2B5F8A] flex items-center justify-center flex-shrink-0">
        <Sparkles className="w-4 h-4 text-white" />
      </div>
      <div className="max-w-[82%] space-y-3">
        <p className="text-sm text-gray-700 ml-1">{message.content}</p>
        {message.recommendations?.map((proj, idx) => (
          <div key={idx} className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden card-hover">
            <div className="px-4 py-2 bg-gradient-to-r from-[#F7F3EB] to-white border-b border-gray-50 flex items-center justify-between">
              <span className="text-sm font-semibold text-[#1A3A56]">{proj.name}</span>
              <span className="text-xs font-medium text-[#D4A853] bg-[#FDFBF5] px-2 py-0.5 rounded-full border border-amber-100">
                {proj.price}
              </span>
            </div>
            <div className="px-4 py-3 space-y-2">
              <div>
                <span className="text-xs text-gray-400">适用人群</span>
                <p className="text-sm text-gray-700">{proj.suitable}</p>
              </div>
              <div>
                <span className="text-xs text-gray-400">治疗原理</span>
                <p className="text-sm text-gray-700">{proj.principle}</p>
              </div>
              <div>
                <span className="text-xs text-gray-400">恢复期</span>
                <p className="text-sm text-gray-700">{proj.recovery}</p>
              </div>
              {proj.qa && proj.qa.length > 0 && (
                <div className="mt-2 pt-2 border-t border-gray-100">
                  <span className="text-xs text-gray-400">常见问题</span>
                  {proj.qa.map((q, qIdx) => (
                    <p key={qIdx} className="text-xs text-gray-600 mt-1">💡 {q}</p>
                  ))}
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
