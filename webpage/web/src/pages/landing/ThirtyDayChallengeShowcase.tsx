import { Sparkles, Camera, Map, Edit3, Share2 } from 'lucide-react';

export const ThirtyDayChallengeShowcase = () => (
  <section id="thirty-day-challenge" className="cv-auto py-24 bg-white overflow-hidden">
    <div className="max-w-7xl mx-auto px-4">
      <div className="flex flex-col lg:flex-row-reverse items-center gap-16">
        <div className="flex-1 space-y-8">
          <div className="inline-flex items-center gap-2 px-4 py-2 bg-emerald-50 text-emerald-600 rounded-full text-sm font-black uppercase tracking-wider">
            <Sparkles className="w-4 h-4" />
            生活实验 · 挑战中心
          </div>
          
          <h2 className="text-4xl sm:text-5xl font-black text-slate-900 leading-tight tracking-tight">
            30天找到全新自我：<br />
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-emerald-500 to-teal-500">
              给平淡生活加点新鲜感
            </span>
          </h2>
          
          <p className="text-lg sm:text-xl text-slate-600 leading-relaxed">
            支持从公共题库挑选或导入 `.txt/.md` 专属挑战清单。通过 30 件微小但特别的小事重新找回感受力，并已全面接入规划中心容量预留与番茄专注联动。
          </p>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
            <div className="flex gap-4 p-6 bg-slate-50/50 rounded-3xl border border-slate-100 hover:shadow-md transition">
              <div className="w-12 h-12 bg-emerald-50 text-emerald-600 rounded-2xl flex items-center justify-center shrink-0">
                <Map className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">随机探索</h3>
                <p className="text-sm text-slate-500 leading-relaxed">随时抽取一件未完成的小事，打破日常的按部就班。</p>
              </div>
            </div>

            <div className="flex gap-4 p-6 bg-slate-50/50 rounded-3xl border border-slate-100 hover:shadow-md transition">
              <div className="w-12 h-12 bg-amber-50 text-amber-600 rounded-2xl flex items-center justify-center shrink-0">
                <Edit3 className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">记录感受</h3>
                <p className="text-sm text-slate-500 leading-relaxed">随时写下当下的灵光一现与感受，将瞬间化作永恒。</p>
              </div>
            </div>

            <div className="flex gap-4 p-6 bg-slate-50/50 rounded-3xl border border-slate-100 hover:shadow-md transition">
              <div className="w-12 h-12 bg-blue-50 text-blue-600 rounded-2xl flex items-center justify-center shrink-0">
                <Camera className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">影像日记</h3>
                <p className="text-sm text-slate-500 leading-relaxed">为每一个挑战配上专属照片，建立属于你的回忆墙。</p>
              </div>
            </div>

            <div className="flex gap-4 p-6 bg-slate-50/50 rounded-3xl border border-slate-100 hover:shadow-md transition">
              <div className="w-12 h-12 bg-rose-50 text-rose-600 rounded-2xl flex items-center justify-center shrink-0">
                <Share2 className="w-6 h-6" />
              </div>
              <div>
                <h3 className="font-black text-slate-900 mb-1">专属报告</h3>
                <p className="text-sm text-slate-500 leading-relaxed">一键生成精美的长图报告，记录并分享这段难忘旅程。</p>
              </div>
            </div>
          </div>
        </div>

        <div className="flex-1 relative">
          <div className="absolute -inset-4 bg-gradient-to-tr from-emerald-400/20 to-teal-500/20 blur-3xl rounded-[3rem]"></div>
          <div className="relative bg-white p-4 rounded-[3rem] shadow-2xl border border-slate-100 transform lg:-rotate-2 hover:rotate-0 transition-transform duration-700">
            <img 
              src="./thirty_day_challenge.jpg"
              alt="30 Day Life Experiment Preview" 
              loading="lazy"
              className="rounded-[2.5rem] w-full shadow-inner object-cover"
            />
            
            {/* Floating decorative elements */}
            <div className="absolute -bottom-6 -left-6 bg-white p-6 rounded-3xl shadow-xl border border-slate-100 hidden sm:block animate-bounce-slow">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 bg-gradient-to-br from-emerald-400 to-teal-500 rounded-full flex items-center justify-center shadow-lg shadow-emerald-500/30">
                  <Camera className="text-white w-6 h-6" />
                </div>
                <div>
                  <p className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">今日发现</p>
                  <p className="text-xl font-black text-slate-900 truncate max-w-[120px]">去一家新餐厅</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>
);
