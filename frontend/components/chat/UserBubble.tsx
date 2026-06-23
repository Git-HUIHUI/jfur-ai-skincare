import type { Message } from "@/lib/types"

export function UserBubble({ message }: { message: Message }) {
  // 安全处理内容 - 防止循环引用
  const safeContent = (() => {
    if (typeof message.content === 'string') return message.content
    try {
      // 尝试用自定义 replacer 防止循环引用
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
  
  // 安全处理图片预览
  const safeImagePreview = typeof message.image_preview === 'string' 
    ? message.image_preview 
    : null

  return (
    <div className="flex justify-end">
      <div className="max-w-[80%] bg-[#2B5F8A] text-white rounded-2xl rounded-br-md px-4 py-2.5 shadow-sm">
        {safeImagePreview && (
          <div className="mb-2 rounded-lg overflow-hidden">
            {/* blob: URL 用原生 img，Next/Image 不支持本地 object URL */}
            <img
              src={safeImagePreview}
              alt="上传的照片"
              className="w-full h-auto max-w-[200px] rounded-lg"
            />
          </div>
        )}
        <p className="text-sm leading-relaxed whitespace-pre-wrap">{safeContent}</p>
      </div>
    </div>
  )
}
