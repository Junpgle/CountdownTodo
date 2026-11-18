import { Sparkles, Layers, Radio, Link2, Command, LayoutGrid } from 'lucide-react';

export const WindowsIslandShowcase = ({ imageSrc }: { imageSrc?: string }) => (
  <section id="windows-island" className="cv-auto py-24 sm:py-36 bg-slate-900 text-white relative overflow-hidden">
    <div className="absolute inset-0 bg-gradient-to-b from-slate-900 via-purple-900/10 to-slate-900 pointer-events-none"></div>
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
      <div className="flex flex-col lg:flex-row items-center gap-12 lg:gap-20">
        {/* 左侧：Windows + macOS 双端灵动岛效果图 */}
        <div className="w-full lg:w-7/12 order-2 lg:order-1 space-y-6">
          <div className="relative group">
            <div className="absolute -inset-10 bg-purple-500/20 blur-[120px] rounded-full pointer-events-none"></div>
            {imageSrc ? (
              <img
                src={imageSrc}
                alt="Windows 桌面灵动岛效果图"
                loading="lazy"
                className="relative w-full rounded-2xl md:rounded-3xl shadow-2xl shadow-purple-500/20 transform group-hover:-translate-y-1 transition-all duration-700"
              />
            ) : (
              <div className="relative w-full aspect-[16/10] rounded-2xl md:rounded-3xl bg-slate-800/60 flex flex-col items-center justify-center gap-3 border border-dashed border-slate-600 shadow-2xl">
                <Sparkles className="w-10 h-10 text-slate-500" />
                <p className="text-slate-500 text-sm font-medium">island_screenshot.webp</p>
              </div>
            )}
            {/* 悬浮徽章 */}
            <div className="absolute -top-4 -right-3 bg-purple-600 text-white px-4 py-2 rounded-2xl shadow-xl flex items-center gap-2 animate-bounce-subtle border border-purple-400 z-20">
              <span className="relative flex h-3 w-3">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-white opacity-75"></span>
                <span className="relative inline-flex rounded-full h-3 w-3 bg-green-300"></span>
              </span>
              <span className="font-black text-xs uppercase tracking-widest">Windows Island</span>
            </div>
          </div>

          <div className="grid sm:grid-cols-2 gap-5 items-stretch">
            <div className="relative group rounded-2xl md:rounded-3xl bg-slate-950/90 border border-white/10 p-3 shadow-2xl flex flex-col">
              <div className="flex items-center justify-between px-2 pb-2 text-xs font-bold text-slate-300">
                <span className="inline-flex items-center gap-1.5">
                  <Command className="w-3.5 h-3.5 text-sky-400" /> macOS 灵动岛拖放 &amp; 专注
                </span>
                <span className="text-[10px] text-sky-300 uppercase tracking-wider">QuickLook</span>
              </div>
              <img
                src="./macos_island_screenshot.jpg"
                alt="macOS 灵动岛展开态：跨设备专注、音乐歌词、中转暂存与文件拖放"
                loading="lazy"
                className="w-full rounded-xl md:rounded-2xl shadow-inner object-contain my-auto"
              />
            </div>

            <div className="relative group rounded-2xl md:rounded-3xl bg-slate-950/90 border border-white/10 p-3 shadow-2xl flex flex-col">
              <div className="flex items-center justify-between px-2 pb-2 text-xs font-bold text-slate-300">
                <span className="inline-flex items-center gap-1.5">
                  <LayoutGrid className="w-3.5 h-3.5 text-emerald-400" /> 桌面小组件群
                </span>
                <span className="text-[10px] text-emerald-300 uppercase tracking-wider">Widgets</span>
              </div>
              <img
                src="./desktop_widgets_v2.jpg"
                alt="桌面小组件：今日习惯、今日课程、今日待办、倒数日"
                loading="lazy"
                className="w-full rounded-xl md:rounded-2xl shadow-inner object-contain my-auto"
              />
            </div>
          </div>
        </div>

        {/* 右侧：文字内容 */}
        <div className="w-full lg:w-5/12 order-1 lg:order-2">
          <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-purple-500/20 text-purple-400 rounded-lg text-sm font-bold uppercase tracking-widest mb-6 sm:mb-8">
            <Sparkles className="w-5 h-5" /> Windows · macOS · 全平台小组件
          </div>
          <h2 className="text-4xl sm:text-5xl lg:text-6xl font-black mb-6 sm:mb-8 leading-tight tracking-tight text-transparent bg-clip-text bg-gradient-to-br from-white to-slate-400">
            双端桌面灵动岛<br />与全平台桌面小组件
          </h2>
          <p className="text-slate-400 text-lg sm:text-xl mb-10 leading-relaxed font-medium">
            Windows 栈式状态机悬浮胶囊、macOS 原生菜单栏专注倒计时与可拖放灵动岛，再配合 Android / 平板桌面小组件——把待办地点、课表、专注进度与近期账单铺在每一块屏幕上。
          </p>
          <ul className="space-y-5">
            {[
              {
                icon: <Layers className="w-5 h-5 text-purple-400" />,
                title: 'Windows 悬浮灵动胶囊',
                desc: '时钟 / 专注 / 提醒三态切换，12 种状态栈式防误触保护，拖动位置跨会话持久化。',
              },
              {
                icon: <Command className="w-5 h-5 text-sky-400" />,
                title: 'macOS 灵动岛拖放 AI 识待办 & QuickLook',
                desc: '把图片、文件或聊天文本直接拖进 macOS 灵动岛，即刻 AI 创建待办并支持 QuickLook 预览；菜单栏常驻倒计时并适配低电量策略。',
              },
              {
                icon: <LayoutGrid className="w-5 h-5 text-emerald-400" />,
                title: 'Android & 平板桌面小组件 (v7.23–v7.24)',
                desc: '支持展示待办与固定日程地点信息、今日课表、专注状态；平板大屏小组件新增近期记账账单列表直览。',
              },
              {
                icon: <Link2 className="w-5 h-5 text-amber-400" />,
                title: '剪贴板速开与专注侧翼联动',
                desc: 'Windows 自动检测剪贴板 URL 弹出「已复制」卡片，10 秒无操作自动收起；macOS 专注期间展开灵动岛侧翼。',
              },
              {
                icon: <Radio className="w-5 h-5 text-rose-400" />,
                title: 'IPC 双通道 & WebSocket 实时同步',
                desc: '一端开启或完成番茄钟，全设备灵动岛与小组件毫秒级同步状态更新。',
              },
            ].map((item, idx) => (
              <li key={idx} className="flex gap-4">
                <div className="w-11 h-11 rounded-2xl bg-slate-800 flex items-center justify-center shrink-0 border border-slate-700 shadow-inner">
                  {item.icon}
                </div>
                <div>
                  <h4 className="text-lg font-bold text-white mb-1">{item.title}</h4>
                  <p className="text-slate-400 text-sm leading-relaxed">{item.desc}</p>
                </div>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  </section>
);
