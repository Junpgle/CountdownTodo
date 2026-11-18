import { Users, Search, ShieldCheck, Zap, History, UserCheck, GanttChartSquare } from 'lucide-react';

export const CollaborationSearchShowcase = () => {
  return (
    <section id="collaboration-search" className="cv-auto py-24 sm:py-36 bg-white relative overflow-hidden">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Team Collaboration Section */}
        <div className="flex flex-col lg:flex-row items-center gap-16 mb-32">
          <div className="flex-1 order-2 lg:order-1">
            <div className="relative group">
              <div className="absolute -inset-4 bg-gradient-to-r from-blue-500 to-indigo-600 rounded-[2.5rem] opacity-20 blur-2xl group-hover:opacity-30 transition duration-1000"></div>
              <div className="relative bg-slate-50 rounded-[2rem] border border-slate-200 overflow-hidden shadow-2xl">
                <div className="p-6 border-b border-slate-200 bg-white flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div className="w-3 h-3 rounded-full bg-red-400"></div>
                    <div className="w-3 h-3 rounded-full bg-amber-400"></div>
                    <div className="w-3 h-3 rounded-full bg-emerald-400"></div>
                  </div>
                  <div className="px-4 py-1 bg-slate-100 rounded-full text-xs font-bold text-slate-400 tracking-wider uppercase">Team &amp; Gantt</div>
                  <div className="w-8"></div>
                </div>
                <div className="aspect-[16/10] bg-slate-50 flex items-center justify-center p-8">
                  <img
                    src="./team_collab_mockup.png"
                    alt="团队协作界面"
                    loading="lazy"
                    className="w-full h-full object-cover rounded-xl shadow-lg border border-slate-200"
                    onError={(e) => {
                      (e.target as HTMLImageElement).style.display = 'none';
                      const parent = (e.target as HTMLImageElement).parentElement;
                      if (parent) {
                        const fallback = document.createElement('div');
                        fallback.className = 'flex flex-col items-center gap-4 text-slate-400 text-center';
                        fallback.innerHTML = `<div><p class="font-bold">团队协作管理</p><p class="text-xs">展示成员列表、任务分发与同步状态</p></div>`;
                        parent.appendChild(fallback);
                      }
                    }}
                  />
                </div>
              </div>
            </div>
          </div>
          <div className="flex-1 order-1 lg:order-2">
            <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-blue-50 text-blue-600 rounded-full text-sm font-bold mb-6">
              <Users className="w-5 h-5" /> 团队协作与全景甘特图
            </div>
            <h2 className="text-4xl sm:text-5xl font-black text-slate-900 mb-6 leading-tight tracking-tight">
              多人协同，<br />双模式透明推进
            </h2>
            <p className="text-slate-500 text-lg mb-8 leading-relaxed font-medium">
              创建或加入群组团队，发布置顶公告，支持「共同协作（一人勾选全员完成）」与「各自独立打卡（互不覆盖状态冲突）」双模式；搭配全景瀑布流、甘特图与团队活跃热力图（支持 7/14/30 天缩放），项目排期一目了然。
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
              {[
                { icon: <GanttChartSquare className="w-5 h-5 text-blue-500" />, title: '瀑布流与甘特图', desc: '双指缩放 7/14/30 天跨度，直观俯瞰任务周期与贡献热力图。' },
                { icon: <ShieldCheck className="w-5 h-5 text-emerald-500" />, title: '独立/共同双模式', desc: '支持共同完成或每人独立打卡，彻底避免多人状态冲突。' },
                { icon: <History className="w-5 h-5 text-amber-500" />, title: '操作审计 & 置顶公告', desc: '成员改动可追溯，管理员置顶公告直达成员首页顶部。' },
                { icon: <UserCheck className="w-5 h-5 text-indigo-500" />, title: 'WebSocket 毫秒同步', desc: '成员状态改动实时推送，配合冲突收件箱保障一致。' },
              ].map((item, i) => (
                <div key={i} className="flex gap-4 p-4 rounded-2xl border border-slate-100 hover:border-blue-200 hover:bg-blue-50/30 transition-all duration-300">
                  <div className="shrink-0">{item.icon}</div>
                  <div>
                    <h4 className="font-bold text-slate-900 mb-1">{item.title}</h4>
                    <p className="text-sm text-slate-500 leading-relaxed">{item.desc}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Global Search & Settings Search Section */}
        <div className="flex flex-col lg:flex-row items-center gap-16">
          <div className="flex-1">
            <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-purple-50 text-purple-600 rounded-full text-sm font-bold mb-6">
              <Search className="w-5 h-5" /> 全局搜索 &amp; 设置直达面板
            </div>
            <h2 className="text-4xl sm:text-5xl font-black text-slate-900 mb-6 leading-tight tracking-tight">
              全维度检索，<br />功能与数据一秒直达
            </h2>
            <p className="text-slate-500 text-lg mb-8 leading-relaxed font-medium">
              一处搜索待办、课程、账单、日记与时间日志；v7.22 起更支持<strong>设置中心实时搜功能</strong>与命令面板直达，搜口语词就能一秒跳进深层配置页。
            </p>
            <div className="space-y-4">
              {[
                '自然语言日期解析：输入“昨天”、“本周五”或“10月24日”聚合当天全部记录',
                '全数据类型覆盖：待办、课程、记账流水、私密日记、时间日志与屏幕使用时长',
                '设置中心实时搜：搜“调休”、“纯黑”、“手环”、“备份”直达深层子页面',
                '功能探索百宝箱：内置关键词检索与未体验引导进度清单，老用户也能挖出隐藏神技',
              ].map((text, i) => (
                <div key={i} className="flex items-center gap-3 text-slate-700 font-bold group">
                  <div className="w-6 h-6 rounded-full bg-purple-100 text-purple-600 flex items-center justify-center text-xs shrink-0 group-hover:scale-110 transition duration-300">
                    {i + 1}
                  </div>
                  <span>{text}</span>
                </div>
              ))}
            </div>
          </div>
          <div className="flex-1">
            <div className="relative group">
              <div className="absolute -inset-4 bg-gradient-to-r from-purple-500 to-pink-600 rounded-[2.5rem] opacity-20 blur-2xl group-hover:opacity-30 transition duration-1000"></div>
              <div className="relative bg-slate-900 rounded-[2rem] border border-white/10 overflow-hidden shadow-2xl">
                <div className="p-4 bg-white/5 border-b border-white/10 flex items-center gap-4">
                  <div className="w-2.5 h-2.5 rounded-full bg-red-500"></div>
                  <div className="w-2.5 h-2.5 rounded-full bg-amber-500"></div>
                  <div className="w-2.5 h-2.5 rounded-full bg-emerald-500"></div>
                  <div className="flex-1 flex justify-center">
                    <div className="bg-white/10 px-4 py-1 rounded-full text-[10px] font-bold text-slate-400 uppercase tracking-widest">Global &amp; Settings Search</div>
                  </div>
                </div>
                <div className="p-6">
                  <div className="flex items-center gap-4 bg-white/5 rounded-2xl px-6 py-4 mb-8 border border-white/10">
                    <Search className="w-6 h-6 text-slate-400" />
                    <div className="text-slate-300 font-bold tracking-tight flex items-center gap-2">
                      <span>搜索“昨天”或“液态玻璃 / 调休”...</span>
                      <Zap className="w-4 h-4 text-amber-400" />
                    </div>
                  </div>
                  <div className="relative rounded-xl overflow-hidden border border-white/5 shadow-2xl aspect-[16/10]">
                    <img src="./search_results_mockup.png" alt="Search Results Mockup" loading="lazy" className="w-full h-full object-cover" />
                    <div className="absolute inset-0 bg-gradient-to-t from-slate-900/60 to-transparent"></div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
