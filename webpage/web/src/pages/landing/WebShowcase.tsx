import { MonitorSmartphone, LayoutDashboard, ChevronRight, PieChart } from 'lucide-react';

export const WebShowcase = ({ onOpenWeb }: { onOpenWeb: () => void }) => (
  <section id="web" className="py-24 sm:py-40 bg-slate-900 overflow-hidden relative">
    <div className="absolute inset-0 bg-gradient-to-b from-slate-900 via-indigo-900/20 to-slate-900 pointer-events-none"></div>
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
      <div className="text-center mb-20">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-indigo-500/20 text-indigo-400 rounded-lg text-sm font-bold uppercase tracking-widest mb-6">
          <MonitorSmartphone className="w-5 h-5" /> Cloud Desktop Station
        </div>
        <h2 className="text-4xl sm:text-6xl font-black mb-6 tracking-tight text-white">Web Pro 全球网页工作站</h2>
        <p className="text-slate-400 text-lg sm:text-xl max-w-3xl mx-auto leading-relaxed font-medium">
          无需下载，任何设备打开浏览器即刻进入。专为桌面大屏重构的 Dashboard 布局，深度整合智能课表、待办分栏与数据仪表盘。
        </p>
      </div>

      <div className="grid lg:grid-cols-2 gap-12 lg:gap-20 items-center">
        <div className="space-y-10 order-2 lg:order-1">
          <div className="group bg-slate-800/50 p-3 rounded-[2.5rem] shadow-2xl border border-white/5 transform hover:-translate-y-2 transition-all duration-700">
            <div className="flex items-center gap-2 px-6 py-4 border-b border-white/5 bg-white/5 rounded-t-[2.2rem]">
               <div className="flex gap-1.5">
                  <div className="w-3 h-3 rounded-full bg-red-500/50"></div>
                  <div className="w-3 h-3 rounded-full bg-amber-500/50"></div>
                  <div className="w-3 h-3 rounded-full bg-green-500/50"></div>
               </div>
               <span className="text-xs font-mono text-slate-500 ml-4 font-bold tracking-tight">app.countdowntodo.com</span>
            </div>
            <img src="./11.webp" alt="网页版主界面" className="w-full rounded-b-[2rem] shadow-inner" />
            <div className="p-8">
              <h3 className="text-2xl font-bold text-white mb-3 flex items-center gap-2">
                <LayoutDashboard className="w-6 h-6 text-indigo-400" />
                全能工作仪表盘
              </h3>
              <p className="text-slate-400 leading-relaxed">左侧 50% 嵌入自适应周视图课表，右侧 1/5 聚焦倒计时，4/5 管理待办清单。完美利用屏幕宽度，效率一眼全收。</p>
            </div>
          </div>
          <button onClick={onOpenWeb} className="w-full flex items-center justify-center gap-3 bg-indigo-600 text-white px-10 py-5 rounded-2xl font-black text-xl hover:bg-indigo-700 transition shadow-2xl shadow-indigo-500/40 hover:-translate-y-1 active:scale-95">
            立即开启网页站 <ChevronRight className="w-6 h-6" />
          </button>
        </div>

        <div className="order-1 lg:order-2 lg:pt-32">
          <div className="group bg-slate-800/50 p-3 rounded-[2.5rem] shadow-2xl border border-white/5 transform hover:-translate-y-2 transition-all duration-700">
            <div className="flex items-center gap-2 px-6 py-4 border-b border-white/5 bg-white/5 rounded-t-[2.2rem]">
               <span className="text-xs font-mono text-slate-500 font-bold tracking-widest uppercase">Insight analytics</span>
            </div>
            <img src="./12.webp" alt="网页版屏幕使用时间" className="w-full rounded-b-[2rem] shadow-inner" />
            <div className="p-8">
              <h3 className="text-2xl font-bold text-white mb-3 flex items-center gap-2">
                <PieChart className="w-6 h-6 text-emerald-400" />
                深度时耗看板
              </h3>
              <p className="text-slate-400 leading-relaxed">全屏精美统计图表，多维度分析手机、平板与电脑的使用时长分布，还原最真实的时间流向，让掌控力跃然屏上。</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>
);
