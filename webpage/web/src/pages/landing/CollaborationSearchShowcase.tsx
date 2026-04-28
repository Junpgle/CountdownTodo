import { Users, Search, ShieldCheck, Zap, History, UserCheck } from 'lucide-react';

export const CollaborationSearchShowcase = () => {
  return (
    <section id="collaboration-search" className="py-24 sm:py-40 bg-white relative overflow-hidden">
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
                  <div className="px-4 py-1 bg-slate-100 rounded-full text-xs font-bold text-slate-400 tracking-wider uppercase">Team Dashboard</div>
                  <div className="w-8"></div>
                </div>
                <div className="aspect-[16/10] bg-slate-50 flex items-center justify-center p-8">
                   <img 
                    src="./team_collab_mockup.png" 
                    alt="团队协作界面" 
                    className="w-full h-full object-cover rounded-xl shadow-lg border border-slate-200"
                    onError={(e) => {
                        (e.target as HTMLImageElement).style.display = 'none';
                        const parent = (e.target as HTMLImageElement).parentElement;
                        if (parent) {
                          const fallback = document.createElement('div');
                          fallback.className = 'flex flex-col items-center gap-4 text-slate-400 text-center';
                          fallback.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg><div><p class="font-bold">团队协作管理</p><p class="text-xs">展示成员列表、任务分发与同步状态</p></div>`;
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
              <Users className="w-5 h-5" /> 团队协作 2.0
            </div>
            <h2 className="text-4xl sm:text-5xl font-black text-slate-900 mb-6 leading-tight tracking-tight">
              多人协同，<br />从未如此高效透明
            </h2>
            <p className="text-slate-500 text-lg mb-8 leading-relaxed font-medium">
              基于 Uni-Sync 4.0 架构，支持多人实时编辑同一份待办清单。内置完善的冲突检测与自动合并机制，确保团队数据始终处于最新状态。
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
              {[
                { icon: <ShieldCheck className="w-5 h-5 text-emerald-500" />, title: "冲突自动解决", desc: "LWW (Last Write Wins) 策略确保数据一致性。" },
                { icon: <History className="w-5 h-5 text-amber-500" />, title: "操作审计日志", desc: "每一笔改动均可追溯，保障团队协作安全。" },
                { icon: <Zap className="w-5 h-5 text-purple-500" />, title: "毫秒级同步", desc: "团队成员改动瞬间触达，无需手动刷新。" },
                { icon: <UserCheck className="w-5 h-5 text-indigo-500" />, title: "完善的审核机制", desc: "支持团队加入申请与角色审批，保障清单私密性。" }
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

        {/* Global Search Section */}
        <div className="flex flex-col lg:flex-row items-center gap-16">
          <div className="flex-1">
            <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-purple-50 text-purple-600 rounded-full text-sm font-bold mb-6">
              <Search className="w-5 h-5" /> 全局搜索引擎
            </div>
            <h2 className="text-4xl sm:text-5xl font-black text-slate-900 mb-6 leading-tight tracking-tight">
              全维度检索，<br />一切尽在掌控
            </h2>
            <p className="text-slate-500 text-lg mb-8 leading-relaxed font-medium">
              不再迷失在海量数据中。强大的全局搜索引擎支持毫秒级检索待办、时间戳记录、甚至应用使用历史。配合自然语言日期识别，找寻过去如同呼吸般简单。
            </p>
            <div className="space-y-4">
              {[
                "支持自然语言搜索：搜索“昨天”、“本周五”或具体日期",
                "跨类型聚合：同时呈现待办、番茄钟、应用使用频率",
                "深度链接导航：搜索结果一键直达统计图表或任务详情",
                "高效索引优化：数十万条记录，依然保持瞬间响应"
              ].map((text, i) => (
                <div key={i} className="flex items-center gap-3 text-slate-700 font-bold group">
                  <div className="w-6 h-6 rounded-full bg-purple-100 text-purple-600 flex items-center justify-center text-xs group-hover:scale-110 transition duration-300">
                    {i + 1}
                  </div>
                  {text}
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
                    <div className="bg-white/10 px-4 py-1 rounded-full text-[10px] font-bold text-slate-400 uppercase tracking-widest">Global Search Context</div>
                  </div>
                </div>
                <div className="p-6">
                  <div className="flex items-center gap-4 bg-white/5 rounded-2xl px-6 py-4 mb-8 border border-white/10">
                    <Search className="w-6 h-6 text-slate-400" />
                    <div className="text-slate-300 font-bold tracking-tight">搜索“昨天”的应用使用情况...</div>
                  </div>
                  <div className="relative rounded-xl overflow-hidden border border-white/5 shadow-2xl aspect-[16/10]">
                    <img src="./search_results_mockup.png" alt="Search Results Mockup" className="w-full h-full object-cover" />
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
