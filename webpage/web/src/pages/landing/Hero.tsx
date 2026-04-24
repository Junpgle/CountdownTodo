import { type ReactElement, cloneElement, useState, useEffect } from 'react';
import { Download, Globe, Github, Sparkles, Watch, Smartphone, Monitor, Database, Shield } from 'lucide-react';

export const Hero = ({ version, date }: { version?: string, date?: string }) => {
  const [activeMessageIndex, setActiveMessageIndex] = useState(0);
  
  const messages = [
    `版本: v${version || '4.0.0'}`,
    `更新于: ${date || '2026-04-24'}`,
  ];

  useEffect(() => {
    const timer = setInterval(() => {
      setActiveMessageIndex((prev) => (prev + 1) % messages.length);
    }, 4000);
    return () => clearInterval(timer);
  }, [messages.length]);

  return (
    <section className="relative min-h-[95vh] flex items-center pt-24 pb-20 overflow-hidden bg-white selection:bg-indigo-100">
      {/* Dynamic Background */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        {/* Animated Spotlight */}
        <div className="absolute top-1/2 left-1/2 w-[140%] h-[140%] bg-[radial-gradient(circle_at_center,_var(--tw-gradient-from)_0%,_transparent_60%)] from-indigo-50/40 animate-spotlight -z-10"></div>
        
        {/* Floating Blobs */}
        <div className="absolute top-[-10%] left-[-10%] w-[45%] h-[45%] bg-gradient-to-br from-indigo-200/40 to-blue-200/40 rounded-full blur-[120px] animate-blob"></div>
        <div className="absolute top-[20%] right-[-10%] w-[40%] h-[40%] bg-gradient-to-br from-purple-200/40 to-pink-200/40 rounded-full blur-[120px] animate-blob animation-delay-2000"></div>
        <div className="absolute bottom-[-10%] left-[20%] w-[35%] h-[35%] bg-gradient-to-br from-rose-200/40 to-orange-200/40 rounded-full blur-[120px] animate-blob animation-delay-4000"></div>
        
        {/* Particles */}
        {[...Array(8)].map((_, i) => (
          <div 
            key={i} 
            className="absolute bg-indigo-500/10 rounded-full blur-[2px] animate-float"
            style={{
              width: Math.random() * 25 + 10 + 'px',
              height: Math.random() * 25 + 10 + 'px',
              left: Math.random() * 100 + '%',
              top: Math.random() * 100 + '%',
              animationDelay: Math.random() * 5 + 's',
              animationDuration: Math.random() * 12 + 8 + 's'
            }}
          />
        ))}

        <div className="absolute inset-0 opacity-[0.04]" style={{ backgroundImage: 'radial-gradient(#000 1.2px, transparent 1.2px)', backgroundSize: '48px 48px' }}></div>
      </div>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10 w-full">
        <div className="flex flex-col lg:flex-row items-center gap-20 lg:gap-32">
          
          {/* Content Column */}
          <div className="flex-[1.2] text-center lg:text-left">
            <div className="inline-flex items-center gap-3 px-5 py-2.5 rounded-full bg-slate-900 shadow-2xl shadow-slate-200 text-white text-xs sm:text-sm font-bold mb-10 animate-fade-in-up">
              <Sparkles className="w-4 h-4 text-amber-400" />
              <span>Uni-Sync 4.0 已就绪</span>
              <div className="w-px h-4 bg-white/20 mx-1"></div>
              <div className="relative h-5 overflow-hidden min-w-[140px] text-white/60">
                {messages.map((msg, i) => (
                  <div 
                    key={i} 
                    className={`absolute inset-0 transition-all duration-700 flex items-center whitespace-nowrap ${
                      i === activeMessageIndex ? 'translate-y-0 opacity-100' : 'translate-y-full opacity-0'
                    }`}
                  >
                    {msg}
                  </div>
                ))}
              </div>
            </div>
            
            <h1 className="text-6xl sm:text-7xl md:text-8xl xl:text-9xl font-black tracking-tight mb-8 leading-[0.95] text-slate-900">
              未来效率<br />
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-indigo-600 via-violet-600 via-purple-600 via-pink-600 to-rose-600 animate-text-gradient">觉醒时刻</span>
            </h1>
            
            <p className="text-xl sm:text-2xl text-slate-500 max-w-2xl mx-auto lg:mx-0 mb-14 leading-relaxed font-medium">
              跨越设备鸿沟。原生 C++ 极致桌面性能、Material 3 沉浸交互、D1 分布式同步架构。一处落笔，全球共鸣。
            </p>
            
            <div className="flex flex-col sm:flex-row items-center justify-center lg:justify-start gap-5 sm:gap-8 mb-16">
              <a href="#download" className="group relative flex items-center justify-center gap-4 bg-indigo-600 text-white px-12 py-6 rounded-[2rem] text-xl font-bold hover:bg-indigo-700 transition-all shadow-[0_20px_50px_rgba(79,70,229,0.3)] hover:-translate-y-1.5 w-full sm:w-auto overflow-hidden">
                <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/20 to-transparent -translate-x-full group-hover:translate-x-full transition-transform duration-1000"></div>
                <Download className="w-7 h-7" /> 立即下载
              </a>
              <a href="#download" className="group flex items-center justify-center gap-4 bg-white/50 backdrop-blur-xl text-slate-900 border border-slate-200 px-12 py-6 rounded-[2rem] text-xl font-bold hover:bg-white transition-all hover:-translate-y-1.5 shadow-xl shadow-slate-100/50 w-full sm:w-auto">
                <Globe className="w-7 h-7 text-indigo-600 group-hover:rotate-12 transition-transform" /> 网页站入口
              </a>
            </div>

            {/* Premium Badges Grid */}
            <div className="grid grid-cols-3 sm:grid-cols-5 gap-6 sm:gap-10 opacity-30 grayscale hover:grayscale-0 transition-all duration-700">
               {[
                 { icon: <Monitor />, label: "Windows" },
                 { icon: <Smartphone />, label: "Android" },
                 { icon: <Watch />, label: "Mi Band" },
                 { icon: <Globe />, label: "Web Pro" },
                 { icon: <Github />, label: "Source" }
               ].map((item, i) => (
                 <div key={i} className="flex flex-col items-center lg:items-start gap-2 group cursor-default">
                    <div className="p-2 rounded-lg bg-slate-100 group-hover:bg-indigo-50 transition-colors">
                      {cloneElement(item.icon as ReactElement<any>, { className: "w-5 h-5 group-hover:text-indigo-600" })}
                    </div>
                    <span className="text-[10px] font-black uppercase tracking-[0.2em]">{item.label}</span>
                 </div>
               ))}
            </div>
          </div>

          {/* Visual Column */}
          <div className="flex-1 relative w-full perspective-2000">
            <div className="relative z-10 animate-float transform -rotate-y-12 rotate-x-6 hover:rotate-0 transition-all duration-[1.5s] ease-out-expo group">
               {/* Dashboard Mockup */}
               <div className="bg-white rounded-[3.5rem] shadow-[0_50px_100px_-20px_rgba(0,0,0,0.15)] border border-slate-100 overflow-hidden aspect-[4/3] relative">
                  <div className="absolute top-0 left-0 w-full h-14 bg-slate-50/50 backdrop-blur-md border-b border-slate-100 flex items-center px-8 gap-2.5">
                     <div className="w-3.5 h-3.5 rounded-full bg-rose-400 shadow-inner shadow-rose-600/20"></div>
                     <div className="w-3.5 h-3.5 rounded-full bg-amber-400 shadow-inner shadow-amber-600/20"></div>
                     <div className="w-3.5 h-3.5 rounded-full bg-emerald-400 shadow-inner shadow-emerald-600/20"></div>
                  </div>
                  <div className="p-10 pt-24 space-y-8">
                     <div className="flex gap-8">
                        <div className="flex-1 h-40 bg-gradient-to-br from-indigo-50 to-blue-50 rounded-[2.5rem] border border-indigo-100/50 p-8 flex flex-col justify-between relative overflow-hidden group/card">
                           <div className="absolute -right-4 -top-4 w-24 h-24 bg-indigo-500/5 rounded-full blur-2xl group-hover/card:scale-150 transition-transform"></div>
                           <div className="w-12 h-12 bg-white rounded-2xl flex items-center justify-center shadow-sm">
                              <Database className="w-6 h-6 text-indigo-600" />
                           </div>
                           <div>
                              <div className="text-[10px] font-black text-indigo-400 uppercase tracking-widest mb-1">Total Syncs</div>
                              <div className="text-3xl font-black text-slate-900">1.2M+</div>
                           </div>
                        </div>
                        <div className="flex-1 h-40 bg-gradient-to-br from-purple-50 to-pink-50 rounded-[2.5rem] border border-purple-100/50 p-8 flex flex-col justify-between relative overflow-hidden group/card">
                           <div className="absolute -right-4 -top-4 w-24 h-24 bg-purple-500/5 rounded-full blur-2xl group-hover/card:scale-150 transition-transform"></div>
                           <div className="w-12 h-12 bg-white rounded-2xl flex items-center justify-center shadow-sm">
                              <Shield className="w-6 h-6 text-purple-600" />
                           </div>
                           <div>
                              <div className="text-[10px] font-black text-purple-400 uppercase tracking-widest mb-1">Security</div>
                              <div className="text-3xl font-black text-slate-900">AES-256</div>
                           </div>
                        </div>
                     </div>
                     <div className="space-y-4">
                        {[1, 2].map(i => (
                          <div key={i} className="h-20 bg-white border border-slate-100 rounded-3xl flex items-center px-8 gap-5 shadow-sm hover:shadow-md transition-shadow">
                             <div className="w-10 h-10 rounded-2xl bg-slate-50 flex items-center justify-center">
                                <Sparkles className="w-5 h-5 text-indigo-400" />
                             </div>
                             <div className="flex-1 space-y-2">
                                <div className="w-40 h-4 bg-slate-200 rounded-full"></div>
                                <div className="w-24 h-2 bg-slate-100 rounded-full"></div>
                             </div>
                             <div className="px-4 py-1.5 bg-emerald-50 text-emerald-600 text-[10px] font-black uppercase rounded-full">Completed</div>
                          </div>
                        ))}
                     </div>
                  </div>
               </div>

               {/* Floating Premium Widgets */}
               <div className="absolute -top-12 -right-12 bg-white/80 backdrop-blur-2xl p-8 rounded-[3rem] shadow-[0_30px_60px_rgba(0,0,0,0.1)] border border-white flex flex-col items-center animate-float animation-delay-2000 z-20 w-56 transform hover:scale-110 transition-transform">
                  <div className="w-16 h-16 rounded-full bg-gradient-to-tr from-rose-500 to-orange-400 flex items-center justify-center mb-5 shadow-lg shadow-rose-200">
                    <Watch className="w-8 h-8 text-white" />
                  </div>
                  <div className="text-xs font-black text-slate-400 uppercase tracking-widest mb-1">Mi Band Pro</div>
                  <div className="text-3xl font-black text-slate-900 tracking-tighter">04:20</div>
                  <div className="text-[10px] font-medium text-slate-500 mt-2">Next Task in 5m</div>
               </div>

               <div className="absolute -bottom-16 -left-12 bg-slate-900 p-8 rounded-[3rem] shadow-[0_40px_80px_rgba(0,0,0,0.3)] border border-white/10 animate-float animation-delay-4000 z-20 w-64 transform hover:scale-110 transition-transform">
                  <div className="flex items-center gap-4 mb-6">
                     <div className="w-12 h-12 bg-gradient-to-tr from-indigo-600 to-blue-500 rounded-2xl flex items-center justify-center shadow-lg shadow-indigo-500/20">
                        <Sparkles className="w-7 h-7 text-white" />
                     </div>
                     <div className="text-left">
                        <div className="text-[10px] font-black text-white/40 uppercase tracking-[0.2em] mb-1">Engine</div>
                        <div className="text-lg font-bold text-white leading-none">Uni-Sync 4.0</div>
                     </div>
                  </div>
                  <div className="space-y-3">
                    <div className="flex justify-between text-[10px] font-bold text-white/30 uppercase tracking-widest">
                       <span>Stability</span>
                       <span>99.9%</span>
                    </div>
                    <div className="w-full h-2 bg-white/10 rounded-full overflow-hidden p-[2px]">
                       <div className="w-[99.9%] h-full bg-gradient-to-r from-indigo-500 to-blue-400 rounded-full shadow-[0_0_10px_rgba(99,102,241,0.5)]"></div>
                    </div>
                  </div>
               </div>
            </div>
            
            <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[130%] h-[130%] bg-[radial-gradient(circle,_var(--tw-gradient-from)_0%,_transparent_70%)] from-indigo-500/10 blur-[120px] rounded-full -z-10 animate-pulse"></div>
          </div>
        </div>
      </div>
    </section>
  );
};

