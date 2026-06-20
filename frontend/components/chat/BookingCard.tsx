import { Sparkles, MapPin, Phone } from "lucide-react"
import type { Message } from "@/lib/types"

export function BookingCard({ message }: { message: Message }) {
  const stores = message.stores || []

  return (
    <div className="flex items-start gap-2.5">
      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-[#D4A853] to-[#2B5F8A] flex items-center justify-center flex-shrink-0">
        <Sparkles className="w-4 h-4 text-white" />
      </div>
      <div className="max-w-[82%] bg-white rounded-2xl rounded-tl-sm shadow-sm border border-gray-100 overflow-hidden">
        <div className="px-4 py-1.5 bg-gradient-to-r from-[#F0FFF4] to-white border-b border-gray-50">
          <span className="text-xs font-medium text-green-700">🏥 预约引导</span>
        </div>
        <div className="px-4 py-3">
          <p className="text-sm text-gray-700 leading-relaxed whitespace-pre-wrap">{message.content}</p>
        </div>
        <div className="px-4 pb-4 flex gap-2">
          <a
            href="https://www.jfur.com"
            target="_blank"
            rel="noopener noreferrer"
            className="flex-1 py-2 bg-[#2B5F8A] text-white text-sm rounded-lg hover:bg-[#1A3A56] transition-colors flex items-center justify-center gap-1.5"
          >
            <MapPin className="w-4 h-4" />
            查看门店
          </a>
          {stores[0]?.phone && (
            <a
              href={`tel:${stores[0].phone}`}
              className="flex-1 py-2 border border-[#2B5F8A] text-[#2B5F8A] text-sm rounded-lg hover:bg-[#F0F7FF] transition-colors text-center"
            >
              <Phone className="w-4 h-4 inline mr-1" />
              拨打电话
            </a>
          )}
        </div>
      </div>
    </div>
  )
}
