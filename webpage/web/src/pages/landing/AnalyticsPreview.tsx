import { Database } from 'lucide-react';

export const AnalyticsPreview = () => (
  <section id="analytics" className="py-24 bg-white text-center">
    <div className="max-w-6xl mx-auto px-4">
      <h2 className="text-4xl font-black mb-10 text-slate-900 tracking-tight">数据聚合，一眼万年</h2>
      <div className="bg-slate-900 p-10 sm:p-20 rounded-[4rem] text-left relative overflow-hidden group shadow-2xl">
         <div className="absolute top-0 right-0 w-96 h-96 bg-indigo-600/10 blur-[120px]"></div>
         <div className="flex flex-col md:flex-row gap-16 items-center">
            <div className="flex-1">
               <div className="flex items-center gap-4 mb-8">
                  <div className="w-12 h-12 bg-indigo-600 rounded-2xl flex items-center justify-center shadow-lg shadow-indigo-500/30">
                     <Database className="text-white w-6 h-6" />
                  </div>
                  <span className="text-white font-black text-2xl tracking-tight">云端字典自动映射</span>
               </div>
               <p className="text-slate-400 leading-relaxed mb-10 text-lg">
                 后端 D1 数据库自动处理全平台应用名映射。无论包名如何差异，在看板中都将合并为最直观的分类，为您还原最真实的时间流向。
               </p>
               <div className="flex flex-wrap gap-3">
                  {['影音娱乐', '学习办公', '系统应用', '通讯社交', '游戏人生'].map(tag => (
                    <span key={tag} className="px-5 py-2 bg-white/5 text-slate-300 text-sm font-bold rounded-full border border-white/5 hover:bg-white/10 transition cursor-default">
                      {tag}
                    </span>
                  ))}
               </div>
            </div>
            <div className="flex-1 grid grid-cols-3 gap-3 w-full opacity-40 group-hover:opacity-100 transition-all duration-700 transform group-hover:rotate-1">
               {[1,2,3,4,5,6,7,8,9].map(i => (
                 <div key={i} className="aspect-square bg-white/5 rounded-2xl border border-white/5 flex flex-col items-center justify-center p-4 hover:border-indigo-500/50 transition">
                   <div className="w-10 h-10 bg-indigo-500/20 rounded-full mb-3 blur-[2px]"></div>
                   <div className="w-12 h-2 bg-white/10 rounded-full mb-1"></div>
                   <div className="w-8 h-1 bg-white/5 rounded-full"></div>
                 </div>
               ))}
            </div>
         </div>
      </div>
    </div>
  </section>
);
