import { History, ExternalLink, Sparkles, Zap, Target, BarChart3, Award, CalendarClock } from 'lucide-react';

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
  <section id="timeline" className="cv-auto py-24 bg-slate-50 overflow-hidden">
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div className="flex flex-col lg:flex-row items-center gap-16">
        <div className="flex-1 space-y-8">
          <div className="inline-flex items-center gap-2 px-4 py-2 bg-indigo-50 text-indigo-600 rounded-full text-sm font-black uppercase tracking-wider">
            <Sparkles className="w-4 h-4" />
            v7.23 升级 · 专注统计与个人时间轴
          </div>

          <h2 className="text-4xl sm:text-5xl font-black text-slate-900 leading-tight tracking-tight">
            个人时间轴与复盘：<br />
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-indigo-600 to-violet-600">
              洞察每一秒的价值
            </span>
          </h2>

          <p className="text-lg sm:text-xl text-slate-600 leading-relaxed">
            聚合番茄钟专注、时间日志拖拽补录、屏幕使用时间（含 Windows Tai 数据）、待办完成率与个人记账收支。v7.23 新增统计看板日/周/月/年快速选择跳转与下钻，时间轴更支持课表与固定日程虚线占位对比。
          </p>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
            <div className="flex gap-4 p-5 bg-white rounded-3xl border border-slate-100 shadow-sm hover:shadow-md transition">
              <div className="w-12 h-12 bg-emerald-50 text-emerald-600 rounded-2xl flex items-center justify-center shrink-0">
                <Zap className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">多维下钻统计看板</h3>
                <p className="text-sm text-slate-500 leading-relaxed">日/周/月/年视图快速跳转与数据下钻，支持按年份筛选纵览成长曲线。</p>
              </div>
            </div>

            <div className="flex gap-4 p-5 bg-white rounded-3xl border border-slate-100 shadow-sm hover:shadow-md transition">
              <div className="w-12 h-12 bg-amber-50 text-amber-600 rounded-2xl flex items-center justify-center shrink-0">
                <CalendarClock className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">时间日志拖拽补录 &amp; 占位</h3>
                <p className="text-sm text-slate-500 leading-relaxed">网格上直接框选补录时间，自动投影课程与固定日程虚线占位，直观对比偏差。</p>
              </div>
            </div>

            <div className="flex gap-4 p-5 bg-white rounded-3xl border border-slate-100 shadow-sm hover:shadow-md transition">
              <div className="w-12 h-12 bg-indigo-50 text-indigo-600 rounded-2xl flex items-center justify-center shrink-0">
                <BarChart3 className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">多端屏幕使用聚合</h3>
                <p className="text-sm text-slate-500 leading-relaxed">聚合手机与电脑端 Tai 时长，区分“生产力”与“干扰”，告别屏幕焦虑。</p>
              </div>
            </div>

            <div className="flex gap-4 p-5 bg-white rounded-3xl border border-slate-100 shadow-sm hover:shadow-md transition">
              <div className="w-12 h-12 bg-violet-50 text-violet-600 rounded-2xl flex items-center justify-center shrink-0">
                <Award className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">勋章墙 &amp; 长图导出</h3>
                <p className="text-sm text-slate-500 leading-relaxed">解锁数十枚专注与坚持成就勋章，支持一键导出阶段性长图报告。</p>
              </div>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-4 pt-2">
            <button
              onClick={openTimelineReportInApp}
              className="inline-flex items-center justify-center gap-3 bg-indigo-600 hover:bg-indigo-700 text-white px-9 py-4 rounded-[2rem] text-base sm:text-lg font-black transition shadow-xl shadow-indigo-500/25 active:scale-95 group"
            >
              前往 App 查看我的报告
              <ExternalLink className="w-5 h-5 group-hover:translate-x-1 group-hover:-translate-y-1 transition-transform" />
            </button>
            <div className="inline-flex items-center gap-2 text-xs font-bold text-slate-500">
              <Target className="w-4 h-4 text-indigo-500" />
              支持番茄钟专注期系统勿扰联动
              <History className="w-4 h-4 text-indigo-500 ml-2" />
              支持历史记录批量打标
            </div>
          </div>
        </div>

        <div className="flex-1 relative flex justify-center">
          <div className="absolute -inset-4 bg-gradient-to-tr from-indigo-500/20 to-violet-500/20 blur-3xl rounded-[3rem]"></div>
          <div className="relative w-full max-w-[330px] bg-white p-3 rounded-[2.75rem] shadow-2xl border border-slate-100 transform lg:rotate-2 hover:rotate-0 transition-transform duration-700">
            <img
              src="./personal_timeline_v2.jpg"
              alt="Personal Timeline Insight Preview"
              loading="lazy"
              className="rounded-[2.2rem] w-full h-auto object-contain shadow-inner"
            />

            {/* Floating decorative elements */}
            <div className="absolute -bottom-6 -left-8 bg-white p-5 rounded-3xl shadow-xl border border-slate-100 hidden sm:block animate-bounce-slow">
              <div className="flex items-center gap-4">
                <div className="w-10 h-10 bg-emerald-500 rounded-full flex items-center justify-center">
                  <Zap className="text-white w-5 h-5" />
                </div>
                <div>
                  <p className="text-[10px] font-bold text-slate-400 uppercase">今日专注</p>
                  <p className="text-xl font-black text-slate-900">2 小时 9 分</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>
);
