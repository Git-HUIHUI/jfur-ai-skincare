import Image from "next/image"
import type { Message } from "@/lib/types"

export function UserBubble({ message }: { message: Message }) {
  return (
    <div className="flex justify-end">
      <div className="max-w-[80%] bg-[#2B5F8A] text-white rounded-2xl rounded-br-md px-4 py-2.5 shadow-sm">
        {message.image_preview && (
          <div className="mb-2 rounded-lg overflow-hidden">
            <Image src={message.image_preview} alt="上传的照片" width={200} height={200} className="w-full h-auto" />
          </div>
        )}
        <p className="text-sm leading-relaxed whitespace-pre-wrap">{message.content}</p>
      </div>
    </div>
  )
}
