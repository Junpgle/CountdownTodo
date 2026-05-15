import { Wifi, FileUp, Zap, Smartphone, Monitor, ArrowLeftRight } from 'lucide-react';
import { MobileFrame, MonitorFrame } from '../../components/Frames';

export const LANSyncShowcase = () => {
  return (
    <section id="lan-sync" className="py-24 sm:py-40 bg-slate-50 relative overflow-hidden">
      <div className="absolute top-0 left-0 w-full h-full opacity-[0.02] pointer-events-none" style={{ backgroundImage: 'radial-gradient(#6366f1 1px, transparent 1px)', backgroundSize: '40px 40px' }}></div>
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center relative z-10">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-indigo-100 text-indigo-700 rounded-full text-sm font-bold mb-6">
          <Wifi className="w-5 h-5" /> 局域网极速同步
        </div>
        <h2 className="text-4xl sm:text-5xl lg:text-6xl font-black mb-6 text-slate-900 tracking-tight">
          断网也能用，<br />同步不等待
        </h2>
        <p className="text-slate-500 text-lg sm:text-xl max-w-3xl mx-auto leading-relaxed mb-20 px-4">
          内置点对点 (P2P) 同步协议。只要设备在同一局域网内，即可免去服务器中转，实现毫秒级数据同步与大文件疾速互传。
        </p>

        <div className="relative max-w-5xl mx-auto mb-24">
          <div className="grid md:grid-cols-2 gap-8 relative z-20">
            <div className="bg-white p-8 rounded-[2.5rem] shadow-xl border border-slate-100 flex flex-col items-center group hover:-translate-y-2 transition-all duration-500">
              <div className="w-20 h-20 bg-indigo-50 text-indigo-600 rounded-3xl flex items-center justify-center mb-6 group-hover:scale-110 transition duration-500">
                <Zap className="w-10 h-10" />
              </div>
              <h3 className="text-2xl font-bold text-slate-900 mb-4">免流极速同步</h3>
              <p className="text-slate-500 leading-relaxed text-center">
                无需消耗任何互联网流量。基于本地网络协议，不论是万条待办记录还是复杂的课程表，瞬间完成多端一致性校验。
              </p>
            </div>
            <div className="bg-white p-8 rounded-[2.5rem] shadow-xl border border-slate-100 flex flex-col items-center group hover:-translate-y-2 transition-all duration-500">
              <div className="w-20 h-20 bg-emerald-50 text-emerald-600 rounded-3xl flex items-center justify-center mb-6 group-hover:scale-110 transition duration-500">
                <FileUp className="w-10 h-10" />
              </div>
              <h3 className="text-2xl font-bold text-slate-900 mb-4">跨端文件互传</h3>
              <p className="text-slate-500 leading-relaxed text-center">
                不止是数据，更是传输利器。支持手机与电脑间快速发送图片、文档及安装包，打破设备间的“隔离墙”。
              </p>
            </div>
          </div>
          
          {/* Connecting devices visualization */}
          <div className="flex flex-col lg:flex-row items-center justify-center gap-12 lg:gap-24 relative z-10 mt-20">
             <div className="w-full lg:w-1/2 max-w-[600px] group transition-transform duration-500 hover:scale-[1.02]">
                <MonitorFrame src="./lan_sync_desktop.jpg" />
                <div className="mt-6 flex items-center justify-center gap-2 text-slate-400 font-bold uppercase tracking-widest text-xs">
                   <Monitor className="w-4 h-4" /> Windows Desktop
                </div>
             </div>

             <div className="hidden lg:flex flex-col items-center gap-4">
                <div className="w-16 h-16 rounded-full bg-indigo-600 text-white flex items-center justify-center shadow-2xl shadow-indigo-200 animate-pulse">
                   <ArrowLeftRight className="w-8 h-8" />
                </div>
                <div className="text-indigo-600 font-black text-xs uppercase tracking-tighter">P2P Syncing</div>
             </div>

             <div className="w-[60%] lg:w-1/4 max-w-[280px] group transition-transform duration-500 hover:scale-[1.05] hover:-rotate-2">
                <MobileFrame src="./lan_sync_mockup.png" />
                <div className="mt-6 flex items-center justify-center gap-2 text-slate-400 font-bold uppercase tracking-widest text-xs">
                   <Smartphone className="w-4 h-4" /> Android Mobile
                </div>
             </div>

             {/* Background Glow */}
             <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[120%] h-[120%] bg-indigo-500/5 blur-[120px] rounded-full -z-10 pointer-events-none"></div>
          </div>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-8 max-w-4xl mx-auto">
          {[
            { label: "自动发现", desc: "零配置连接" },
            { label: "AES 加密", desc: "局域网安全保障" },
            { label: "双向同步", desc: "状态无缝流转" },
            { label: "零延迟", desc: "即刻操作响应" }
          ].map((item, i) => (
            <div key={i} className="text-center">
              <div className="text-2xl font-black text-slate-900 mb-1 tracking-tight">{item.label}</div>
              <div className="text-xs font-bold text-slate-400 uppercase tracking-widest">{item.desc}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};
