import Image from "next/image"
import { Sparkles } from "lucide-react"
import type { Message } from "@/lib/types"

export function PreviewCard({ message }: { message: Message }) {
  return (
    <div className="flex items-start gap-2.5">
      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#D4A853] to-[#2B5F8A] flex items-center justify-center flex-shrink-0">
        <Sparkles className="w-4 h-4 text-white" />
      </div>
      <div className="max-w-[82%] bg-white rounded-2xl rounded-tl-sm shadow-sm border border-gray-100 overflow-hidden">
        <div className="px-4 py-1.5 bg-gradient-to-r from-[#FEF3E8] to-white border-b border-gray-50">
          <span className="text-xs font-medium text-[#D4A853]">🎨 效果模拟图</span>
        </div>
        <div className="p-4">
          {message.image_urls?.map((url, idx) => (
            <div key={idx} className="rounded-lg overflow-hidden">
              <Image src={url} alt={`效果模拟图 ${idx + 1}`} width={512} height={512} className="w-full h-auto" />
            </div>
          ))}
          {message.disclaimer && (
            <p className="text-xs text-amber-600 mt-3 text-center bg-amber-50/50 rounded-lg py-1.5">
              {message.disclaimer}
            </p>
          )}
        </div>
      </div>
    </div>
  )
}
