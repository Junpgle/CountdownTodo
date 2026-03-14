import { Download, Globe, Github, Sparkles } from 'lucide-react';

export const Hero = () => (
  <section className="relative pt-28 pb-16 sm:pt-36 sm:pb-20 lg:pt-52 lg:pb-40 overflow-hidden px-4">
    <div className="max-w-7xl mx-auto relative z-10 text-center">
      <div className="inline-flex items-center gap-2 px-3 py-1.5 sm:px-4 sm:py-2 rounded-full bg-indigo-50 border border-indigo-100 text-indigo-700 text-xs sm:text-sm font-bold mb-6 sm:mb-8 animate-bounce-subtle">
        <Sparkles className="w-4 h-4 text-indigo-500" />
        真正实现跨设备、全平台的极致协同
      </div>
      <h1 className="text-4xl sm:text-5xl md:text-7xl lg:text-8xl font-black tracking-tighter mb-6 sm:mb-8 leading-[1.15] text-slate-900">
        多端联动，<br className="sm:hidden" />
        <span className="bg-clip-text text-transparent bg-gradient-to-r from-indigo-600 via-purple-600 to-pink-500">效率觉醒</span>
      </h1>
      <p className="text-lg sm:text-xl md:text-2xl text-slate-500 max-w-3xl mx-auto mb-10 sm:mb-12 leading-relaxed px-2 font-medium">
        原生 C++ 桌面工作站、Material 3 沉浸式移动端、以及全新的 Web Pro 网页控制中心。一处编辑，毫秒全端同步。
      </p>
      <div className="flex flex-col sm:flex-row justify-center gap-4 sm:gap-6 w-full max-w-3xl mx-auto">
        <a href="#download" className="group flex items-center justify-center gap-3 bg-slate-900 text-white px-8 py-4 sm:px-10 sm:py-4 rounded-2xl text-base sm:text-lg font-bold hover:bg-slate-800 transition-all shadow-xl hover:-translate-y-1 w-full sm:w-auto">
          <Download className="w-5 h-5 group-hover:animate-pulse" /> 获取客户端
        </a>
        <a href="#download" className="flex items-center justify-center gap-3 bg-white text-indigo-600 border border-indigo-100 px-8 py-4 sm:px-10 sm:py-4 rounded-2xl text-base sm:text-lg font-bold hover:bg-indigo-50 transition-all hover:-translate-y-1 shadow-md w-full sm:w-auto">
          <Globe className="w-5 h-5" /> 进入网页站
        </a>
        <a href="https://github.com/Junpgle/CountdownTodo" target="_blank" rel="noreferrer" className="flex items-center justify-center gap-3 bg-white text-slate-700 border border-slate-200 px-8 py-4 sm:px-10 sm:py-4 rounded-2xl text-base sm:text-lg font-bold hover:bg-slate-50 transition-all hover:-translate-y-1 shadow-sm w-full sm:w-auto">
          <Github className="w-5 h-5" /> 开源仓库
        </a>
      </div>
    </div>
    <div className="absolute top-0 left-1/2 -translate-x-1/2 w-full h-full -z-10 pointer-events-none opacity-[0.03]" style={{ backgroundImage: 'radial-gradient(#000 1px, transparent 1px)', backgroundSize: '30px 30px' }}></div>
  </section>
);
