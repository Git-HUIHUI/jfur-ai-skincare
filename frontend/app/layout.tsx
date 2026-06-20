import type { Metadata } from "next"
import "./globals.css"

export const metadata: Metadata = {
  title: "晶肤AI美肤助手 - 小肤",
  description: "AI美肤助手，上传面部照片，分析皮肤表面特征，匹配晶肤医美项目方案",
  icons: { icon: "/favicon.ico" },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="zh-CN">
      <body className="min-h-screen bg-[#f5f2eb] antialiased">
        {children}
      </body>
    </html>
  )
}
