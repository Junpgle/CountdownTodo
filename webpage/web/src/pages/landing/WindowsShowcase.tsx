import { Monitor, Cpu } from 'lucide-react';
import { MonitorFrame } from '../../components/Frames';

export const WindowsShowcase = () => (
  <section id="desktop" className="py-24 sm:py-40 bg-slate-900 text-white relative overflow-hidden">
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10 text-center">
      <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-blue-500/20 text-blue-400 rounded-lg text-sm font-bold uppercase tracking-widest mb-8">
        <Monitor className="w-5 h-5" /> Native Desktop
      </div>
      <h2 className="text-4xl sm:text-6xl font-black mb-10 tracking-tight text-white text-center">Windows Lite 极致轻量桌面</h2>
      <p className="text-slate-400 text-lg max-w-3xl mx-auto mb-20 leading-relaxed text-center">
        拒绝臃肿。基于 C++17 与 GDI+ 渲染，独创的悬浮小部件 design，让效率在桌面每一寸像素中自由流淌。
      </p>
      <div className="flex justify-center relative group w-full max-w-[900px] mx-auto pb-20 px-2 sm:px-6">
        <div className="absolute -inset-20 bg-blue-500/10 blur-[120px] rounded-full pointer-events-none"></div>
        <MonitorFrame src="./6.jpg" className="transition-transform duration-700 group-hover:scale-[1.01]" />
        <div className="absolute top-1/4 -left-2 sm:-left-12 z-30 transform -rotate-3 hover:rotate-0 hover:scale-105 transition-all duration-500 w-[40%] max-w-[320px]">
           <div className="bg-slate-800 p-2 md:p-3 rounded-[1.2rem] md:rounded-[2.5rem] shadow-[0_30px_60px_-15px_rgba(0,0,0,0.8)] border border-white/10 overflow-hidden">
              <div className="flex items-center gap-1.5 px-3 py-1.5 md:py-3 border-b border-white/5 bg-white/5 mb-1 rounded-t-xl md:rounded-t-3xl">
                 <div className="w-2 md:w-3 h-2 md:h-3 rounded-full bg-red-500"></div>
                 <span className="text-[8px] md:text-xs font-mono text-slate-400 font-bold tracking-tight">TodoWidget.exe</span>
              </div>
              <img src="./1.jpg" alt="桌面悬浮小部件" className="w-full rounded-lg md:rounded-2xl shadow-inner" />
              <div className="p-2 md:p-4 bg-slate-800/50 text-left">
                 <p className="text-[10px] md:text-sm font-black text-blue-400 mb-0.5 md:mb-1">悬浮微件预览</p>
                 <p className="text-[8px] md:text-xs text-slate-400 font-medium leading-tight">支持像素级 Alpha 透明渲染与桌面无缝贴合</p>
              </div>
           </div>
        </div>
        <div className="absolute -bottom-6 right-2 sm:right-10 bg-indigo-600 p-4 md:p-8 rounded-[1.5rem] md:rounded-[2.5rem] shadow-2xl flex items-center gap-3 md:gap-5 z-40 animate-bounce-subtle border border-white/10">
          <div className="w-8 md:w-14 h-8 md:h-14 bg-white/20 rounded-lg md:rounded-[1.2rem] flex items-center justify-center">
            <Cpu className="w-4 md:w-8 h-4 md:h-8 text-white" />
          </div>
          <div className="text-left">
            <p className="text-[8px] md:text-xs text-indigo-200 uppercase font-black tracking-widest mb-0.5 md:mb-1">Resource</p>
            <p className="text-white text-sm md:text-2xl font-black italic">占用 &lt; 30MB</p>
          </div>
        </div>
      </div>
    </div>
  </section>
);
