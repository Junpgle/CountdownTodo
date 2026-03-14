import { Monitor, Smartphone, Globe, ChevronRight, ArrowRight, HelpCircle, ExternalLink } from 'lucide-react';
import type { AppInfo } from '../../types';

export const DownloadSection = ({
  androidInfo,
  windowsInfo,
  windowsProInfo,
  webInfo,
  onOpenWeb,
  onShowInstallGuide
}: {
  androidInfo: AppInfo;
  windowsInfo: AppInfo;
  windowsProInfo: AppInfo;
  webInfo: AppInfo;
  onOpenWeb: () => void;
  onShowInstallGuide: () => void;
}) => (
  <section id="download" className="py-24 sm:py-48 bg-slate-50 text-center relative overflow-hidden">
    <div className="absolute top-0 left-0 w-full h-px bg-gradient-to-r from-transparent via-slate-200 to-transparent"></div>
    <div className="max-w-[90rem] mx-auto px-4 sm:px-6 lg:px-8">
      <h2 className="text-4xl sm:text-7xl font-black mb-8 text-slate-900 tracking-tighter">准备好开启高效生活了吗？</h2>

      <div className="mb-20">
        <p className="text-slate-500 text-xl font-medium mb-6">全平台支持，数据实时流转，选择适合您的工作方式。</p>

        {/* 备用下载链接徽章 */}
        <div className="inline-flex items-center gap-2 px-4 py-2 bg-blue-50 text-blue-700 rounded-2xl border border-blue-100 shadow-sm hover:bg-blue-100 transition-colors group">
          <ExternalLink className="w-4 h-4 text-blue-500 group-hover:scale-110 transition-transform" />
          <span className="text-sm font-bold">GitHub 下载缓慢？</span>
          <a
            href="https://www.123865.com/s/SCPrVv-8gYi3"
            target="_blank"
            rel="noreferrer"
            className="text-sm font-black underline decoration-2 underline-offset-2 hover:text-blue-900"
          >
            前往备用下载 (123云盘)
          </a>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-6 text-left items-stretch">
        {/* Windows Lite */}
        <div className="p-8 sm:p-10 bg-white rounded-[3rem] border border-slate-200 shadow-sm hover:shadow-2xl hover:border-blue-500 transition-all group flex flex-col relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-blue-500/5 rounded-full blur-3xl group-hover:bg-blue-500/10 transition"></div>
          <div className="w-14 h-14 bg-blue-50 text-blue-600 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 group-hover:rotate-3 transition duration-500 shadow-sm"><Monitor className="w-7 h-7" /></div>
          <h3 className="text-2xl font-black mb-3 text-slate-900 tracking-tight">Windows Lite</h3>
          <p className="text-slate-500 text-sm sm:text-base mb-8 flex-1 leading-relaxed whitespace-pre-line">
             v{windowsInfo.version || '1.0.0'} <br/>
             {windowsInfo.desc || '原生 C++ 极致轻量，常驻桌面微件，给您最纯净的办公体验。'}
          </p>
          <div className="space-y-4">
             <a href={windowsInfo.url || "#"} className="flex items-center justify-center gap-3 bg-blue-600 text-white w-full py-4 rounded-xl font-black text-lg hover:bg-blue-700 transition shadow-xl shadow-blue-500/30">立即下载 <ChevronRight className="w-6 h-6" /></a>
             <div className="flex items-center justify-between px-5 py-3 bg-blue-50 rounded-xl text-xs text-blue-700 font-bold border border-blue-100">
                <span>依赖 Tai 核心服务</span>
                <a href="https://github.com/Planshit/Tai/releases/download/1.5.0.6/Tai1.5.0.6.zip" target="_blank" rel="noreferrer" className="underline hover:text-blue-900">立即前往</a>
             </div>
          </div>
        </div>

        {/* Windows Pro */}
        <div className="p-8 sm:p-10 bg-white rounded-[3rem] border border-slate-200 shadow-sm hover:shadow-2xl hover:border-emerald-500 transition-all group flex flex-col relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-emerald-500/5 rounded-full blur-3xl group-hover:bg-emerald-500/10 transition"></div>
          <div className="w-14 h-14 bg-emerald-50 text-emerald-600 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 group-hover:-rotate-3 transition duration-500 shadow-sm"><Monitor className="w-7 h-7" /></div>
          <h3 className="text-2xl font-black mb-3 text-slate-900 tracking-tight">Windows Pro</h3>
          <p className="text-slate-500 text-sm sm:text-base mb-8 flex-1 leading-relaxed whitespace-pre-line">
             v{windowsProInfo.version || '1.0.0'} <br/>
             {windowsProInfo.desc || '功能最强大的桌面主控制台，支持番茄悬浮窗及完整云端同步数据管理。'}
          </p>
          <div className="space-y-4">
             <a href={windowsProInfo.url || "#"} className="flex items-center justify-center gap-3 bg-emerald-600 text-white w-full py-4 rounded-xl font-black text-lg hover:bg-emerald-700 transition shadow-xl shadow-emerald-500/30">获取 Pro 版 <ChevronRight className="w-6 h-6" /></a>
             <div className="flex items-center justify-between px-5 py-3 bg-emerald-50 rounded-xl text-xs text-emerald-700 font-bold border border-emerald-100">
                <span>依赖 Tai 核心服务</span>
                <a href="https://github.com/Planshit/Tai/releases/download/1.5.0.6/Tai1.5.0.6.zip" target="_blank" rel="noreferrer" className="underline hover:text-emerald-900">立即前往</a>
             </div>
          </div>
        </div>

        {/* Android */}
        <div className="p-8 sm:p-10 bg-white rounded-[3rem] border border-slate-200 shadow-sm hover:shadow-2xl hover:border-purple-500 transition-all group flex flex-col relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-purple-500/5 rounded-full blur-3xl group-hover:bg-purple-500/10 transition"></div>
          <div className="w-14 h-14 bg-purple-50 text-purple-600 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 group-hover:rotate-3 transition duration-500 shadow-sm"><Smartphone className="w-7 h-7" /></div>
          <h3 className="text-2xl font-black mb-3 text-slate-900 tracking-tight">Android Pro</h3>
          <p className="text-slate-500 text-sm sm:text-base mb-8 flex-1 leading-relaxed whitespace-pre-line">
             v{androidInfo.version || '1.0.0'} <br/>
             {androidInfo.desc || '沉浸式 Flutter 交互，Material 3 视觉盛宴，深度屏幕时间 analysis。'}
          </p>
          <a href={androidInfo.url || "#"} className="flex items-center justify-center gap-3 bg-purple-600 text-white w-full py-4 rounded-xl font-black text-lg hover:bg-purple-700 transition shadow-xl shadow-purple-500/30">获取安装包 <ChevronRight className="w-6 h-6" /></a>
        </div>

        {/* Web */}
        <div className="p-8 sm:p-10 bg-white rounded-[3rem] border border-slate-200 shadow-sm hover:shadow-2xl hover:border-indigo-500 transition-all group flex flex-col relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-indigo-500/5 rounded-full blur-3xl group-hover:bg-indigo-500/10 transition"></div>
          <div className="w-14 h-14 bg-indigo-50 text-indigo-600 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 group-hover:-rotate-3 transition duration-500 shadow-sm"><Globe className="w-7 h-7" /></div>
          <h3 className="text-2xl font-black mb-3 text-slate-900 tracking-tight">Web Station</h3>
          <p className="text-slate-500 text-sm sm:text-base mb-8 flex-1 leading-relaxed whitespace-pre-line">
             v{webInfo.version || '1.0.0'} <br/>
             {webInfo.desc || '云端仪表盘，免安装即开即用。深度同步课表与待办，您的跨平台数据中枢。'}
          </p>
          <div className="space-y-4">
            <button onClick={onOpenWeb} className="flex items-center justify-center gap-3 bg-indigo-600 text-white w-full py-4 rounded-xl font-black text-lg hover:bg-indigo-700 transition shadow-xl shadow-indigo-500/30">立即开启 <ArrowRight className="w-6 h-6" /></button>
            <button onClick={onShowInstallGuide} className="flex items-center justify-center gap-2 w-full py-3 rounded-xl font-bold text-sm text-indigo-600 bg-indigo-50 hover:bg-indigo-100 border border-indigo-100 transition">
              <HelpCircle className="w-4 h-4" /> 如何把网页作为 App 安装？
            </button>
          </div>
        </div>
      </div>
    </div>
  </section>
);