import { Download, Globe, Github, Sparkles, ChevronRight, Watch, Smartphone, Monitor } from 'lucide-react';

export const Hero = () => {
  return (
    <section className="relative min-h-[90vh] flex items-center pt-20 pb-20 overflow-hidden bg-white">
      {/* Background Decorations */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-[-10%] left-[-10%] w-[40%] h-[40%] bg-indigo-100/50 rounded-full blur-[120px] animate-blob"></div>
        <div className="absolute top-[20%] right-[-10%] w-[35%] h-[35%] bg-purple-100/50 rounded-full blur-[120px] animate-blob animation-delay-2000"></div>
        <div className="absolute bottom-[-10%] left-[20%] w-[30%] h-[30%] bg-rose-100/50 rounded-full blur-[120px] animate-blob animation-delay-4000"></div>
        
        {/* Floating Particles */}
        {[...Array(6)].map((_, i) => (
          <div 
            key={i} 
            className="absolute bg-indigo-500/10 rounded-full blur-sm animate-float"
            style={{
              width: Math.random() * 20 + 10 + 'px',
              height: Math.random() * 20 + 10 + 'px',
              left: Math.random() * 100 + '%',
              top: Math.random() * 100 + '%',
              animationDelay: Math.random() * 5 + 's',
              animationDuration: Math.random() * 10 + 10 + 's'
            }}
          />
        ))}

        <div className="absolute inset-0 opacity-[0.03]" style={{ backgroundImage: 'radial-gradient(#000 1px, transparent 1px)', backgroundSize: '40px 40px' }}></div>
      </div>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10 w-full">
        <div className="flex flex-col lg:flex-row items-center gap-16 lg:gap-24">
          
          {/* Left Column: Text Content */}
          <div className="flex-1 text-center lg:text-left">
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-slate-900 text-white text-xs sm:text-sm font-bold mb-8 animate-fade-in">
              <Sparkles className="w-4 h-4 text-amber-400" />
              <span>Uni-Sync 4.0 现已发布</span>
              <div className="w-px h-4 bg-white/20 mx-1"></div>
              <span className="text-white/60">跨平台极致协同</span>
            </div>
            
            <h1 className="text-5xl sm:text-6xl md:text-7xl xl:text-8xl font-black tracking-tight mb-8 leading-[1.05] text-slate-900">
              重塑你的<br />
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-indigo-600 via-purple-600 to-pink-500">数字生产力</span>
            </h1>
            
            <p className="text-lg sm:text-xl md:text-2xl text-slate-500 max-w-2xl mx-auto lg:mx-0 mb-12 leading-relaxed font-medium">
              不仅是待办，更是你的全平台时间管家。原生 C++ 桌面端、Flutter 沉浸式移动端与 Web 控制中心，助你跨设备精准把控每一秒。
            </p>
            
            <div className="flex flex-col sm:flex-row items-center justify-center lg:justify-start gap-4 sm:gap-6 mb-12">
              <a href="#download" className="group relative flex items-center justify-center gap-3 bg-indigo-600 text-white px-10 py-5 rounded-2xl text-lg font-bold hover:bg-indigo-700 transition-all shadow-xl shadow-indigo-200 hover:-translate-y-1 w-full sm:w-auto overflow-hidden">
                <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/10 to-transparent -translate-x-full group-hover:translate-x-full transition-transform duration-1000"></div>
                <Download className="w-6 h-6" /> 获取客户端
              </a>
              <a href="#download" className="flex items-center justify-center gap-3 bg-white text-slate-900 border border-slate-200 px-10 py-5 rounded-2xl text-lg font-bold hover:bg-slate-50 transition-all hover:-translate-y-1 shadow-sm w-full sm:w-auto">
                <Globe className="w-6 h-6 text-indigo-600" /> 网页站入口 <ChevronRight className="w-5 h-5 text-slate-300" />
              </a>
            </div>

            {/* Platform Badges */}
            <div className="flex items-center justify-center lg:justify-start gap-8 opacity-40 grayscale hover:grayscale-0 transition-all duration-500">
               <div className="flex items-center gap-2">
                 <Monitor className="w-5 h-5" />
                 <span className="text-xs font-bold uppercase tracking-widest">Windows</span>
               </div>
               <div className="flex items-center gap-2">
                 <Smartphone className="w-5 h-5" />
                 <span className="text-xs font-bold uppercase tracking-widest">Android</span>
               </div>
               <div className="flex items-center gap-2">
                 <Watch className="w-5 h-5" />
                 <span className="text-xs font-bold uppercase tracking-widest">Mi Band 7/8/9</span>
               </div>
               <div className="flex items-center gap-2">
                 <Github className="w-5 h-5" />
                 <span className="text-xs font-bold uppercase tracking-widest">Open Source</span>
               </div>
            </div>
          </div>

          {/* Right Column: Visual Mockup */}
          <div className="flex-1 relative w-full max-w-[600px] lg:max-w-none perspective-1000">
            <div className="relative z-10 animate-float transform -rotate-y-10 rotate-x-2 hover:rotate-0 transition-transform duration-1000 ease-out">
               {/* Main UI Card Mockup */}
               <div className="bg-white rounded-[3rem] shadow-2xl border border-slate-200 overflow-hidden aspect-[4/3] relative">
                  <div className="absolute top-0 left-0 w-full h-12 bg-slate-50 border-b border-slate-100 flex items-center px-6 gap-2">
                     <div className="w-3 h-3 rounded-full bg-red-400"></div>
                     <div className="w-3 h-3 rounded-full bg-amber-400"></div>
                     <div className="w-3 h-3 rounded-full bg-emerald-400"></div>
                  </div>
                  <div className="p-8 pt-20">
                     <div className="flex gap-6 mb-8">
                        <div className="flex-1 h-32 bg-slate-50 rounded-3xl border border-slate-100 p-6 flex flex-col justify-end">
                           <div className="w-12 h-2 bg-indigo-200 rounded-full mb-2"></div>
                           <div className="w-20 h-4 bg-indigo-600 rounded-lg"></div>
                        </div>
                        <div className="flex-1 h-32 bg-slate-50 rounded-3xl border border-slate-100 p-6 flex flex-col justify-end">
                           <div className="w-12 h-2 bg-purple-200 rounded-full mb-2"></div>
                           <div className="w-16 h-4 bg-purple-600 rounded-lg"></div>
                        </div>
                     </div>
                     <div className="space-y-4">
                        {[1, 2, 3].map(i => (
                          <div key={i} className="h-16 bg-white border border-slate-100 rounded-2xl flex items-center px-6 gap-4 shadow-sm">
                             <div className="w-6 h-6 rounded-lg bg-slate-100"></div>
                             <div className="flex-1 space-y-1.5">
                                <div className="w-32 h-3 bg-slate-200 rounded-full"></div>
                                <div className="w-20 h-2 bg-slate-100 rounded-full"></div>
                             </div>
                             <div className="w-12 h-6 bg-indigo-50 rounded-full"></div>
                          </div>
                        ))}
                     </div>
                  </div>
               </div>

               {/* Floating Widgets */}
               <div className="absolute -top-10 -right-10 bg-white p-6 rounded-3xl shadow-2xl border border-slate-100 animate-float animation-delay-2000 z-20 w-48">
                  <div className="flex items-center justify-between mb-4">
                    <span className="text-xs font-black text-slate-400 uppercase">Focusing</span>
                    <div className="w-2 h-2 rounded-full bg-rose-500 animate-pulse"></div>
                  </div>
                  <div className="text-3xl font-black text-slate-900 mb-1">24:59</div>
                  <div className="text-[10px] font-bold text-slate-500">深度学习计划</div>
               </div>

               <div className="absolute -bottom-12 -left-10 bg-slate-900 p-6 rounded-3xl shadow-2xl border border-white/10 animate-float animation-delay-4000 z-20 w-56">
                  <div className="flex items-center gap-3 mb-4">
                     <div className="w-10 h-10 bg-indigo-600 rounded-xl flex items-center justify-center">
                        <Sparkles className="w-6 h-6 text-white" />
                     </div>
                     <div className="text-left">
                        <div className="text-xs font-black text-white/50 uppercase leading-none mb-1">Syncing</div>
                        <div className="text-sm font-bold text-white leading-none">5 Devices</div>
                     </div>
                  </div>
                  <div className="w-full h-1.5 bg-white/10 rounded-full overflow-hidden">
                     <div className="w-2/3 h-full bg-indigo-500"></div>
                  </div>
               </div>
            </div>
            
            {/* Soft Shadow Base */}
            <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[120%] h-[120%] bg-indigo-500/5 blur-[120px] rounded-full -z-10"></div>
          </div>
        </div>
      </div>
    </section>
  );
};
