import { Sparkles, CheckCircle2, Clock, PlusCircle, CalendarClock, CalendarCheck2, ShieldAlert } from 'lucide-react';

export const HabitTrackingShowcase = () => (
  <section id="habit-tracking" className="cv-auto py-24 bg-slate-50 overflow-hidden">
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div className="flex flex-col lg:flex-row items-center gap-16">
        <div className="flex-1 space-y-8">
          <div className="inline-flex items-center gap-2 px-4 py-2 bg-indigo-50 text-indigo-600 rounded-full text-sm font-black uppercase tracking-wider">
            <Sparkles className="w-4 h-4" />
            v7.23 升级 · 四维习惯与专属日历
          </div>

          <h2 className="text-4xl sm:text-5xl font-black text-slate-900 leading-tight tracking-tight">
            全面习惯养成：<br />
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-indigo-500 to-violet-500">
              定制你的专属节律
            </span>
          </h2>

          <p className="text-lg sm:text-xl text-slate-600 leading-relaxed">
            打破单一的“完成”打卡模式。涵盖完成、时长、数量、时间点四维习惯体系，支持按单个习惯筛选专属完成日历、防误触延迟落章，并与规划中心和番茄钟深度联动。
          </p>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
            <div className="flex gap-4 p-5 bg-white rounded-3xl border border-slate-100 shadow-sm hover:shadow-md transition">
              <div className="w-12 h-12 bg-emerald-50 text-emerald-600 rounded-2xl flex items-center justify-center shrink-0">
                <CheckCircle2 className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">完成型打卡</h3>
                <p className="text-sm text-slate-500 leading-relaxed">绑定循环待办或独立打卡，长按防误触延迟落章，适合规律日常。</p>
              </div>
            </div>

            <div className="flex gap-4 p-5 bg-white rounded-3xl border border-slate-100 shadow-sm hover:shadow-md transition">
              <div className="w-12 h-12 bg-blue-50 text-blue-600 rounded-2xl flex items-center justify-center shrink-0">
                <Clock className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">时长型 &amp; 番茄联动</h3>
                <p className="text-sm text-slate-500 leading-relaxed">绑定专注标签或直接以习惯开启番茄钟，专注结束自动落章并纳入规划容量预留。</p>
              </div>
            </div>

            <div className="flex gap-4 p-5 bg-white rounded-3xl border border-slate-100 shadow-sm hover:shadow-md transition">
              <div className="w-12 h-12 bg-amber-50 text-amber-600 rounded-2xl flex items-center justify-center shrink-0">
                <PlusCircle className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">数量型打卡</h3>
                <p className="text-sm text-slate-500 leading-relaxed">自定义加减步长与独立事件记录，精准追踪喝水、俯卧撑等计数目标。</p>
              </div>
            </div>

            <div className="flex gap-4 p-5 bg-white rounded-3xl border border-slate-100 shadow-sm hover:shadow-md transition">
              <div className="w-12 h-12 bg-violet-50 text-violet-600 rounded-2xl flex items-center justify-center shrink-0">
                <CalendarClock className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">时间点打卡</h3>
                <p className="text-sm text-slate-500 leading-relaxed">记录早睡、早起实际发生时间，支持前后容差与免扣卡机制，培养稳定作息。</p>
              </div>
            </div>

            <div className="flex gap-4 p-5 bg-white rounded-3xl border border-slate-100 shadow-sm hover:shadow-md transition sm:col-span-2">
              <div className="w-12 h-12 bg-indigo-50 text-indigo-600 rounded-2xl flex items-center justify-center shrink-0">
                <CalendarCheck2 className="w-6 h-6" />
              </div>
              <div className="flex-1">
                <div className="flex flex-wrap items-center gap-2 mb-1">
                  <h3 className="font-black text-slate-900">按习惯筛选专属完成日历 (v7.23)</h3>
                  <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-indigo-50 text-indigo-700 text-[10px] font-bold">
                    <ShieldAlert className="w-3 h-3" /> 视口驻留防误触
                  </span>
                </div>
                <p className="text-sm text-slate-500 leading-relaxed">
                  日历视图支持按单个习惯筛选查看整月专属打卡完成热力分布与历史回溯补卡，盖章动画严格校验视口可见度，告别切 Tab 误触。
                </p>
              </div>
            </div>
          </div>
        </div>

        <div className="flex-1 relative space-y-6">
          <div className="absolute -inset-4 bg-gradient-to-tr from-indigo-400/20 to-violet-500/20 blur-3xl rounded-[3rem] pointer-events-none"></div>
          <div className="relative bg-white p-3 rounded-[2.25rem] shadow-2xl border border-slate-100 transform lg:rotate-1 hover:rotate-0 transition-transform duration-500">
            <img
              src="./habit_today_v2.jpg"
              alt="习惯中心今日打卡与专注落章"
              loading="lazy"
              className="rounded-[1.75rem] w-full h-auto object-contain shadow-inner"
            />
          </div>
          <div className="relative bg-white p-3 rounded-[2.25rem] shadow-2xl border border-slate-100 transform lg:-rotate-1 hover:rotate-0 transition-transform duration-500">
            <img
              src="./habit_analytics_v2.jpg"
              alt="习惯中心近30天打卡热力图与趋势分析"
              loading="lazy"
              className="rounded-[1.75rem] w-full h-auto object-contain shadow-inner"
            />
          </div>
        </div>
      </div>
    </div>
  </section>
);
