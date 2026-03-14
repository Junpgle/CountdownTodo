import { Tablet as TabletIcon, CheckCircle2 } from 'lucide-react';
import { MobileFrame, TabletFrame } from '../../components/Frames';

export const AndroidShowcase = () => (
  <section id="mobile" className="py-24 sm:py-40 bg-white overflow-hidden text-center">
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div className="flex flex-col lg:flex-row items-center gap-12 lg:gap-16 text-left">
        <div className="lg:w-5/12 w-full pr-0 lg:pr-8">
          <div className="inline-flex items-center gap-2 px-3 py-1 bg-purple-50 text-purple-700 rounded-lg text-xs font-bold uppercase mb-6 sm:mb-8">
            <TabletIcon className="w-4 h-4" /> Cross-Device Mobile
          </div>
          <h2 className="text-4xl sm:text-5xl lg:text-6xl font-black mb-6 sm:mb-8 text-slate-900 leading-tight tracking-tight">Android & Tablet Pro<br/>全设备自适应交互</h2>
          <p className="text-slate-500 text-lg sm:text-xl mb-8 sm:mb-12 leading-relaxed font-medium">
            针对大屏平板与手机进行了深度自适应重构。在手机上享受灵动便捷，在平板上体验沉浸式管理与分屏效率。
          </p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-6 sm:gap-8">
            {[
              { t: "自适应分屏", d: "平板模式自动适配横屏布局，数据展示更丰富。" },
              { t: "Material 3", d: "动态配色系统，根据壁纸自动调整色调。" },
              { t: "极速批量同步", d: "Batch 事务机制，数百条数据毫秒级合并流转。" },
              { t: "深色模式", d: "完美适配系统深色/浅色模式无缝切换。" }
            ].map((item, i) => (
              <div key={i} className="flex gap-4 group">
                <div className="w-10 h-10 rounded-xl bg-indigo-50 flex items-center justify-center shrink-0 mt-1 group-hover:bg-indigo-600 group-hover:text-white transition-colors duration-300">
                  <CheckCircle2 className="w-5 h-5 text-indigo-600 group-hover:text-white" />
                </div>
                <div>
                  <h4 className="font-bold text-slate-900 text-base sm:text-lg mb-1">{item.t}</h4>
                  <p className="text-slate-500 text-sm leading-relaxed">{item.d}</p>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="lg:w-7/12 w-full flex items-center justify-center relative mt-16 lg:mt-0">
          <div className="relative z-20 w-[40%] sm:w-[35%] max-w-[260px] transform -rotate-2 hover:rotate-0 transition-all duration-500">
             <MobileFrame src="./2.jpg" />
             <div className="absolute -bottom-6 left-1/2 -translate-x-1/2 bg-white px-3 py-1.5 sm:px-5 sm:py-2.5 rounded-full shadow-xl border border-slate-100 flex items-center gap-1.5 sm:gap-2">
                <div className="w-2 h-2 rounded-full bg-green-500 animate-pulse"></div>
                <span className="text-[10px] sm:text-xs font-black text-slate-700 uppercase tracking-tighter whitespace-nowrap">Phone</span>
             </div>
          </div>
          <div className="relative z-10 w-[65%] sm:w-[60%] max-w-[550px] -ml-[15%] sm:-ml-[10%] transform translate-y-12 sm:translate-y-20 rotate-2 hover:rotate-0 transition-all duration-500">
             <TabletFrame src="./2-2.jpg" />
             <div className="absolute -bottom-6 left-1/2 -translate-x-1/2 bg-white px-3 py-1.5 sm:px-5 sm:py-2.5 rounded-full shadow-xl border border-slate-100 flex items-center gap-1.5 sm:gap-2">
                <div className="w-2 h-2 rounded-full bg-indigo-500 animate-pulse"></div>
                <span className="text-[10px] sm:text-xs font-black text-slate-700 uppercase tracking-tighter whitespace-nowrap">Tablet Pro</span>
             </div>
          </div>
        </div>
      </div>
    </div>
  </section>
);
