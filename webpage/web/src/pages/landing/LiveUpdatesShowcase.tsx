import { useEffect, useRef } from 'react';
import { BellRing } from 'lucide-react';

export const LiveUpdatesShowcase = () => {
  const videoRef = useRef<HTMLVideoElement>(null);
  useEffect(() => {
    if (videoRef.current) {
      videoRef.current.play().catch(e => { console.log("Auto-play was prevented.", e); });
    }
  }, []);

  return (
    <section id="liveupdates" className="py-24 sm:py-40 bg-slate-900 text-white relative overflow-hidden">
      <div className="absolute inset-0 bg-gradient-to-b from-indigo-900/20 to-slate-900 pointer-events-none"></div>
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        <div className="flex flex-col lg:flex-row items-center gap-12 lg:gap-20 text-left">
          <div className="w-full lg:w-1/2 flex justify-center order-2 lg:order-1">
            <div className="relative w-full max-w-[400px]">
               <div className="absolute -inset-10 bg-indigo-500/30 blur-[100px] rounded-full"></div>
               <div className="relative bg-slate-800 rounded-[2rem] md:rounded-[3rem] p-4 md:p-6 shadow-2xl border border-white/10 transform perspective-1000 rotateY-[5deg] hover:rotateY-0 transition-transform duration-700">
                  <video ref={videoRef} src="./7.mp4" className="w-full rounded-xl md:rounded-2xl shadow-inner object-cover" loop muted autoPlay playsInline style={{ pointerEvents: 'none' }} />
                  <div className="absolute -top-4 -right-4 bg-indigo-600 text-white px-4 py-2 rounded-2xl shadow-xl flex items-center gap-2 animate-bounce-subtle border border-indigo-400">
                    <span className="relative flex h-3 w-3">
                      <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-white opacity-75"></span>
                      <span className="relative inline-flex rounded-full h-3 w-3 bg-green-300"></span>
                    </span>
                    <span className="font-black text-xs uppercase tracking-widest">Live Sync</span>
                  </div>
               </div>
            </div>
          </div>
          <div className="w-full lg:w-1/2 order-1 lg:order-2">
            <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-indigo-500/20 text-indigo-400 rounded-lg text-sm font-bold uppercase tracking-widest mb-6 sm:mb-8">
              <BellRing className="w-5 h-5" /> Android 16+ Ready
            </div>
            <h2 className="text-4xl sm:text-5xl lg:text-6xl font-black mb-6 sm:mb-8 leading-tight tracking-tight text-transparent bg-clip-text bg-gradient-to-br from-white to-slate-400">
              灵动通知栏<br/>待办状态实时流转
            </h2>
            <p className="text-slate-400 text-lg sm:text-xl mb-10 leading-relaxed font-medium">
              全面适配 Android 最新规范。借助 Live Updates 实时活动，无需打开应用，在锁屏和通知栏即可直观把控最重要的待办倒计时。
            </p>
            <ul className="space-y-6">
               {[
                 { title: "锁屏级呈现", desc: "最重要的事，点亮屏幕立刻可见。" },
                 { title: "毫秒级状态同步", desc: "桌面端标记完成，手机锁屏秒级自动清除。" },
                 { title: "深度系统融合", desc: "适配各大厂商灵动交互形态。" }
               ].map((item, idx) => (
                 <li key={idx} className="flex gap-4">
                   <div className="w-12 h-12 rounded-2xl bg-slate-800 flex items-center justify-center shrink-0 border border-slate-700 shadow-inner">
                     <span className="text-indigo-400 font-black text-lg">{idx + 1}</span>
                   </div>
                   <div>
                     <h4 className="text-xl font-bold text-white mb-1">{item.title}</h4>
                     <p className="text-slate-400">{item.desc}</p>
                   </div>
                 </li>
               ))}
            </ul>
          </div>
        </div>
      </div>
    </section>
  );
};
