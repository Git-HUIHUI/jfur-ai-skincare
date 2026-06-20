export function TopBar() {
  return (
    <header className="fixed top-0 left-0 right-0 z-50 bg-white/80 backdrop-blur-md border-b border-gray-200">
      <div className="max-w-3xl mx-auto px-4 h-14 flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          {/* Logo placeholder — replace with actual jfur.com logo */}
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[#2B5F8A] to-[#1A3A56] flex items-center justify-center text-white text-xs font-bold">
            晶
          </div>
          <span className="text-sm font-medium text-gray-500">晶肤医美</span>
        </div>
        <h1 className="text-base font-semibold text-[#2B5F8A] tracking-wide">
          晶肤AI美肤助手
        </h1>
        <div className="w-20" /> {/* spacer for centering */}
      </div>
    </header>
  )
}
