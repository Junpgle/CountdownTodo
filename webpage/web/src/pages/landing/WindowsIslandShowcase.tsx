import { Sparkles, Layers, Radio, Link2 } from 'lucide-react';

export const WindowsIslandShowcase = ({ imageSrc }: { imageSrc?: string }) => (
  <section id="windows-island" className="py-24 sm:py-40 bg-slate-900 text-white relative overflow-hidden">
    <div className="absolute inset-0 bg-gradient-to-b from-slate-900 via-purple-900/10 to-slate-900 pointer-events-none"></div>
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
      <div className="flex flex-col lg:flex-row items-center gap-12 lg:gap-20">

        {/* 左侧：效果图铺满 */}
        <div className="w-full lg:w-7/12 order-2 lg:order-1">
          <div className="relative group">
            <div className="absolute -inset-10 bg-purple-500/20 blur-[120px] rounded-full pointer-events-none"></div>
            {imageSrc ? (
              <img src={imageSrc} alt="Windows 桌面灵动岛效果图" className="relative w-full rounded-2xl md:rounded-3xl shadow-2xl shadow-purple-500/20 transform group-hover:-translate-y-1 transition-all duration-700" />
            ) : (
              <div className="relative w-full aspect-[16/10] rounded-2xl md:rounded-3xl bg-slate-800/60 flex flex-col items-center justify-center gap-3 border border-dashed border-slate-600 shadow-2xl">
                <Sparkles className="w-10 h-10 text-slate-500" />
                <p className="text-slate-500 text-sm font-medium">island_screenshot.jpg</p>
              </div>
            )}
            {/* 悬浮徽章 */}
            <div className="absolute -top-4 -right-3 bg-purple-600 text-white px-4 py-2 rounded-2xl shadow-xl flex items-center gap-2 animate-bounce-subtle border border-purple-400 z-20">
              <span className="relative flex h-3 w-3">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-white opacity-75"></span>
                <span className="relative inline-flex rounded-full h-3 w-3 bg-green-300"></span>
              </span>
              <span className="font-black text-xs uppercase tracking-widest">Island Live</span>
            </div>
          </div>
        </div>

        {/* 右侧：文字内容 */}
        <div className="w-full lg:w-5/12 order-1 lg:order-2">
          <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-purple-500/20 text-purple-400 rounded-lg text-sm font-bold uppercase tracking-widest mb-6 sm:mb-8">
            <Sparkles className="w-5 h-5" /> Desktop Dynamic Island
          </div>
          <h2 className="text-4xl sm:text-5xl lg:text-6xl font-black mb-6 sm:mb-8 leading-tight tracking-tight text-transparent bg-clip-text bg-gradient-to-br from-white to-slate-400">
            桌面灵动岛<br/>专注力实时流转
          </h2>
          <p className="text-slate-400 text-lg sm:text-xl mb-10 leading-relaxed font-medium">
            悬浮在桌面的灵动胶囊，无需打开应用即可掌控专注计时、待办详情与日程提醒。基于栈式状态机架构，12 种状态 push/pop/replace 无栈管理，IPC 双通道毫秒级同步。
          </p>
          <ul className="space-y-6">
            {[
              {
                icon: <Layers className="w-5 h-5 text-purple-400" />,
                title: "桌面悬浮胶囊",
                desc: "时钟 / 专注 / 提醒三态切换，拖动位置跨会话持久化。"
              },
              {
                icon: <Radio className="w-5 h-5 text-purple-400" />,
                title: "栈式状态机",
                desc: "受保护状态拒绝外部 payload 覆盖，完成确认 / 放弃确认 / 提醒弹窗全程防误触。"
              },
              {
                icon: <Link2 className="w-5 h-5 text-purple-400" />,
                title: "剪贴板速开",
                desc: "自动检测剪贴板 URL，灵动胶囊弹出「已复制」卡片，一键打开链接，10 秒无操作自动消失。"
              }
            ].map((item, idx) => (
              <li key={idx} className="flex gap-4">
                <div className="w-12 h-12 rounded-2xl bg-slate-800 flex items-center justify-center shrink-0 border border-slate-700 shadow-inner">
                  {item.icon}
                </div>
                <div>
                  <h4 className="text-xl font-bold text-white mb-1">{item.title}</h4>
                  <p className="text-slate-400">{item.desc}</p>
                </div>
              </li>
            ))}
          </ul>
        </div>

      </div>
    </div>
  </section>
);
