// 手机外框
export const MobileFrame = ({ src, className = "" }: { src: string; className?: string }) => (
  <div className={`relative w-full aspect-[9/19.5] bg-slate-900 rounded-[2rem] md:rounded-[2.5rem] border-[6px] md:border-[10px] border-slate-900 shadow-2xl overflow-hidden ${className}`}>
    <div className="absolute top-3 md:top-4 left-1/2 -translate-x-1/2 w-3 md:w-4 h-3 md:h-4 bg-black rounded-full z-20 shadow-inner" />
    <div className="absolute inset-0 bg-white">
      <img src={src} alt="Mobile App" className="w-full h-full object-cover" onError={(e) => { e.currentTarget.src = 'https://images.unsplash.com/photo-1512941937669-90a1b58e7e9c?auto=format&fit=crop&q=80&w=800'; }} />
    </div>
  </div>
);

// 平板外框 (比例 3:2)
export const TabletFrame = ({ src, className = "" }: { src: string; className?: string }) => (
  <div className={`relative w-full aspect-[3/2] bg-slate-800 rounded-[1.5rem] md:rounded-[2rem] border-[6px] md:border-[12px] border-slate-800 shadow-2xl overflow-hidden ${className}`}>
    <div className="absolute top-1/2 left-2 md:left-3 -translate-y-1/2 w-2 md:w-3 h-2 md:h-3 bg-black rounded-full z-20" />
    <div className="absolute inset-0 bg-white">
      <img src={src} alt="Tablet App" className="w-full h-full object-cover" onError={(e) => { e.currentTarget.src = 'https://images.unsplash.com/photo-1544244015-0df4b3ffc6b0?auto=format&fit=crop&q=80&w=800'; }} />
    </div>
  </div>
);

// 显示器外框
export const MonitorFrame = ({ src, className = "" }: { src: string; className?: string }) => (
  <div className={`flex flex-col items-center w-full ${className}`}>
    <div className="relative w-full aspect-[16/10] bg-slate-800 rounded-t-[1.5rem] md:rounded-t-[2.5rem] border-[8px] md:border-[14px] border-slate-800 shadow-2xl overflow-hidden">
      <div className="absolute inset-0 bg-white">
        <img src={src} alt="Desktop App" className="w-full h-full object-cover" onError={(e) => { e.currentTarget.src = 'https://images.unsplash.com/photo-1498050108023-c5249f4df085?auto=format&fit=crop&q=80&w=800'; }} />
      </div>
    </div>
    <div className="w-1/3 h-6 md:h-10 bg-slate-700 relative">
      <div className="absolute bottom-0 left-1/2 -translate-x-1/2 w-[200%] md:w-72 h-3 md:h-4 bg-slate-900 rounded-t-xl md:rounded-t-2xl" />
    </div>
  </div>
);
