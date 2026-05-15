import { History, ExternalLink, Sparkles, Zap, Target, BarChart3 } from 'lucide-react';

const formatDeepLinkDate = (date: Date) => {
  const yyyy = date.getFullYear();
  const mm = String(date.getMonth() + 1).padStart(2, '0');
  const dd = String(date.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
};

const openTimelineReportInApp = () => {
  const deepLink = `countdowntodo://timeline/report?dimension=daily&date=${formatDeepLinkDate(new Date())}`;
  window.location.href = deepLink;
};

export const PersonalTimelineShowcase = () => (
  <section id="timeline" className="py-24 bg-slate-50 overflow-hidden">
    <div className="max-w-7xl mx-auto px-4">
      <div className="flex flex-col lg:flex-row items-center gap-16">
        <div className="flex-1 space-y-8">
          <div className="inline-flex items-center gap-2 px-4 py-2 bg-indigo-50 text-indigo-600 rounded-full text-sm font-black uppercase tracking-wider">
            <Sparkles className="w-4 h-4" />
            全新特性
          </div>
          
          <h2 className="text-5xl font-black text-slate-900 leading-tight tracking-tight">
            个人时间轴：<br />
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-indigo-600 to-violet-600">
              洞察每一秒的价值
            </span>
          </h2>
          
          <p className="text-xl text-slate-600 leading-relaxed">
            不再只是记录，而是深度复盘。从专注时长到屏幕分配，从早起打卡到深夜冲刺，个人时间轴为您还原最真实的成长轨迹。
          </p>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
            <div className="flex gap-4 p-6 bg-white rounded-3xl border border-slate-100 shadow-sm hover:shadow-md transition">
              <div className="w-12 h-12 bg-emerald-50 text-emerald-600 rounded-2xl flex items-center justify-center shrink-0">
                <Zap className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">节奏可视化</h3>
                <p className="text-sm text-slate-500 leading-relaxed">日、周、月、年全维度复盘，发现你的高效工作节律。</p>
              </div>
            </div>

            <div className="flex gap-4 p-6 bg-white rounded-3xl border border-slate-100 shadow-sm hover:shadow-md transition">
              <div className="w-12 h-12 bg-amber-50 text-amber-600 rounded-2xl flex items-center justify-center shrink-0">
                <Target className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">专注深度分析</h3>
                <p className="text-sm text-slate-500 leading-relaxed">自动识别“Deadline 冲刺”与“提前完成”，量化执行力。</p>
              </div>
            </div>

            <div className="flex gap-4 p-6 bg-white rounded-3xl border border-slate-100 shadow-sm hover:shadow-md transition">
              <div className="w-12 h-12 bg-indigo-50 text-indigo-600 rounded-2xl flex items-center justify-center shrink-0">
                <BarChart3 className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">屏幕分配洞察</h3>
                <p className="text-sm text-slate-500 leading-relaxed">区分“生产力”与“干扰”，告别无意义的屏幕焦虑。</p>
              </div>
            </div>

            <div className="flex gap-4 p-6 bg-white rounded-3xl border border-slate-100 shadow-sm hover:shadow-md transition">
              <div className="w-12 h-12 bg-violet-50 text-violet-600 rounded-2xl flex items-center justify-center shrink-0">
                <History className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">一键导出海报</h3>
                <p className="text-sm text-slate-500 leading-relaxed">生成精美的长图报告，记录并分享你的阶段性成就。</p>
              </div>
            </div>
          </div>

          <div className="pt-4">
            <button
              onClick={openTimelineReportInApp}
              className="inline-flex items-center justify-center gap-3 bg-indigo-600 hover:bg-indigo-700 text-white px-10 py-5 rounded-[2rem] text-lg font-black transition shadow-xl shadow-indigo-500/25 active:scale-95 group"
            >
              前往 App 查看我的报告
              <ExternalLink className="w-5 h-5 group-hover:translate-x-1 group-hover:-translate-y-1 transition-transform" />
            </button>
          </div>
        </div>

        <div className="flex-1 relative">
          <div className="absolute -inset-4 bg-gradient-to-tr from-indigo-500/20 to-violet-500/20 blur-3xl rounded-[3rem]"></div>
          <div className="relative bg-white p-4 rounded-[3rem] shadow-2xl border border-slate-100 transform lg:rotate-2 hover:rotate-0 transition-transform duration-700">
            <img 
              src="./personal_timeline_preview.jpg"
              alt="Personal Timeline Insight Preview" 
              className="rounded-[2.5rem] w-full shadow-inner"
            />
            
            {/* Floating decorative elements */}
            <div className="absolute -bottom-8 -left-8 bg-white p-6 rounded-3xl shadow-xl border border-slate-100 hidden sm:block animate-bounce-slow">
              <div className="flex items-center gap-4">
                <div className="w-10 h-10 bg-emerald-500 rounded-full flex items-center justify-center">
                  <Zap className="text-white w-5 h-5" />
                </div>
                <div>
                  <p className="text-[10px] font-bold text-slate-400 uppercase">今日专注</p>
                  <p className="text-xl font-black text-slate-900">420 min</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>
);
