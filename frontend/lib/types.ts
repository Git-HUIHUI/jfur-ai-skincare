// Shared types for the medical aesthetics AI chat app

export interface Message {
  id: string
  role: "user" | "ai" | "system"
  type: "text" | "analysis" | "followup" | "recommendation" | "preview" | "booking" | "status"
  content: string
  recommendations?: Project[]
  stores?: Store[]
  image_urls?: string[]
  image_preview?: string | null
  disclaimer?: string
  step?: string
}

export interface Project {
  name: string
  suitable: string
  principle: string
  price: string
  recovery: string
  qa?: string[]
}

export interface Store {
  name: string
  address: string
  phone: string
}

export const STATUS_STEPS: Record<string, string> = {
  start: "🔍 开始分析您的皮肤状况...",
  analyze: "🔍 正在分析您的皮肤表面特征...",
  ask_followup: "💬 正在进行追问确认...",
  match_product: "📋 正在匹配适合您的项目方案...",
  human_review: "✅ 方案审核通过...",
  generate_preview: "🎨 正在生成效果模拟图...",
  book_appointment: "🏥 正在准备预约引导...",
}
