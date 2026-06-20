import { Sparkles } from "lucide-react"

export function EmptyState({ onHintClick }: { onHintClick?: (text: string) => void }) {
  const hints = [
    "我想改善痘印和肤色暗沉",
    "T区毛孔粗大怎么办？",
    "推荐什么项目适合敏感肌？",
  ]

  const handleClick = (hint: string) => {
    if (onHintClick) {
      onHintClick(hint)
    }
  }

  return (
    <div className="flex flex-col items-center justify-center py-20 text-gray-400">
      <div className="w-20 h-20 rounded-2xl bg-gradient-to-br from-[#F7F3EB] to-white border border-gray-200 flex items-center justify-center mb-6 shadow-sm">
        <Sparkles className="w-10 h-10 text-[#D4A853]" />
      </div>
      <h2 className="text-lg font-medium text-gray-600 mb-2">你好，我是小肤 ✨</h2>
      <p className="text-sm text-gray-400 text-center max-w-xs">
        上传一张面部照片，告诉我你想改善的皮肤问题，<br />
        我会为你分析并推荐适合的晶肤医美方案
      </p>
      <div className="mt-8 flex flex-wrap gap-2 justify-center max-w-sm">
        {hints.map((hint, i) => (
          <button
            key={i}
            onClick={() => handleClick(hint)}
            className="text-xs px-3 py-1.5 bg-white border border-gray-200 rounded-full text-gray-500 hover:border-[#2B5F8A] hover:text-[#2B5F8A] transition-colors"
          >
            {hint}
          </button>
        ))}
      </div>
    </div>
  )
}
