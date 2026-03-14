import { useEffect, useRef } from 'react';
import { CalendarDays, CheckCircle2 } from 'lucide-react';
import { MobileFrame } from '../../components/Frames';

export const TimetableShowcase = () => {
    const videoRef = useRef<HTMLVideoElement>(null);
    useEffect(() => {
      if (videoRef.current) {
        videoRef.current.play().catch(e => console.log("Auto-play prevented.", e));
      }
    }, []);

    return (
      <section id="timetable" className="py-24 sm:py-40 bg-slate-50 relative overflow-hidden">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <div className="mb-20">
            <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-blue-100 text-blue-700 rounded-full text-sm font-bold mb-6">
              <CalendarDays className="w-5 h-5" /> 智能课表与日历
            </div>
            <h2 className="text-4xl sm:text-5xl lg:text-6xl font-black mb-6 text-slate-900 tracking-tight">打通全平台的行程管家</h2>
            <p className="text-slate-500 text-lg sm:text-xl max-w-3xl mx-auto leading-relaxed px-4">
              不仅是待办，更是你的私人课表。支持多种格式课表数据智能导入，云端同步后，PC 端与移动端将呈现一致的网格化视图，全天候、跨天任务一目了然。
            </p>
          </div>

          <div className="flex flex-col lg:flex-row items-center justify-center gap-12 lg:gap-16 mb-24">
            <div className="w-full lg:w-1/3 flex justify-center order-2 lg:order-1 relative group">
                <div className="absolute inset-0 bg-blue-500/10 blur-[80px] rounded-full pointer-events-none"></div>
                <div className="w-[60%] sm:w-[50%] lg:w-[80%] max-w-[300px] transform group-hover:-translate-y-2 transition-transform duration-500">
                    <MobileFrame src="./9.jpg" />
                </div>
            </div>
            <div className="w-full lg:w-2/3 order-1 lg:order-2 group">
              <div className="bg-white p-2 sm:p-4 rounded-[1.5rem] sm:rounded-[2.5rem] shadow-2xl border border-slate-200 transform group-hover:scale-[1.01] transition-transform duration-500">
                <img src="./8.jpg" alt="PC 端日历课表" className="w-full rounded-xl sm:rounded-2xl border border-slate-100" />
              </div>
            </div>
          </div>

          <div className="max-w-4xl mx-auto bg-slate-900 rounded-[2rem] sm:rounded-[3rem] p-6 sm:p-10 shadow-2xl relative overflow-hidden flex flex-col md:flex-row items-center gap-8 md:gap-12 text-left">
            <div className="absolute -right-20 -top-20 w-64 h-64 bg-indigo-500/30 blur-[100px] rounded-full pointer-events-none"></div>
            <div className="w-full md:w-1/2 order-2 md:order-1">
                <div className="relative rounded-[1.5rem] overflow-hidden border-4 border-slate-800 shadow-inner bg-black aspect-[9/19.5] max-h-[500px] mx-auto md:mx-0">
                    <video ref={videoRef} src="./10.mp4" className="w-full h-full object-cover" loop muted autoPlay playsInline style={{ pointerEvents: 'none' }} />
                </div>
            </div>
            <div className="w-full md:w-1/2 order-1 md:order-2">
               <h3 className="text-2xl sm:text-3xl font-black text-white mb-4">无缝导入，即刻生效</h3>
               <p className="text-slate-400 leading-relaxed mb-6">
                 搭载强大的智能解析引擎。在手机端简单几步操作，即可将整学期的课表载入系统。点击「同步」按钮，数据瞬间流转至云端及 PC 桌面。
               </p>
               <ul className="space-y-3 text-slate-300 text-sm font-medium">
                   <li className="flex items-center gap-2"><CheckCircle2 className="w-4 h-4 text-green-400" /> <span className="font-bold text-white">聚在工大:</span> 支持第三方工具 JSON 数据导入</li>
                   <li className="flex items-center gap-2"><CheckCircle2 className="w-4 h-4 text-green-400" /> <span className="font-bold text-white">西安电子科技大学:</span> 支持标准日历 ICS 格式极速解析</li>
                   <li className="flex items-center gap-2"><CheckCircle2 className="w-4 h-4 text-green-400" /> <span className="font-bold text-white">厦门大学:</span> 深度适配教务系统 HTML/MHTML 网页档案导入</li>
                   <li className="flex items-center gap-2"><CheckCircle2 className="w-4 h-4 text-green-400" /> 自动防重叠布局引擎，动态换行与教室地点提示</li>
               </ul>
            </div>
          </div>
        </div>
      </section>
    );
  };
