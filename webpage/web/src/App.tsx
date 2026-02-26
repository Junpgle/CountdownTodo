import React, { useState, useEffect } from 'react';
import {
  Layers,
  Monitor,
  Smartphone,
  CloudLightning,
  Download,
  Github,
  CheckCircle2,
  BarChart2,
  BellRing,
  Image as ImageIcon,
  RefreshCw,
  Menu,
  X,
  ChevronRight,
  Database,
  Cpu,
  MousePointer2,
  Clock,
  PieChart,
  Activity
} from 'lucide-react';

// --- 子组件: 导航栏 ---
const Navbar = () => {
  const [isScrolled, setIsScrolled] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  useEffect(() => {
    const handleScroll = () => setIsScrolled(window.scrollY > 20);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const navLinks = [
    { name: '核心特性', href: '#features' },
    { name: '桌面端', href: '#desktop' },
    { name: '移动端', href: '#mobile' },
    { name: '屏幕时间', href: '#screentime' },
    { name: '数据看板', href: '#analytics' },
  ];

  return (
    <nav className={`fixed w-full z-50 transition-all duration-500 ${
      isScrolled ? 'bg-white/90 backdrop-blur-xl border-b border-slate-200 shadow-sm' : 'bg-transparent'
    }`}>
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center h-16 sm:h-20">
          <div className="flex items-center gap-2 group cursor-pointer">
            <div className="bg-indigo-600 p-1.5 sm:p-2 rounded-lg group-hover:rotate-12 transition-transform duration-300">
              <Layers className="text-white w-5 h-5 sm:w-6 sm:h-6" />
            </div>
            <span className="font-bold text-xl sm:text-2xl tracking-tight text-slate-900">CountDownTodo</span>
          </div>

          <div className="hidden md:flex space-x-8 lg:space-x-10 items-center">
            {navLinks.map((link) => (
              <a
                key={link.name}
                href={link.href}
                className="text-slate-600 hover:text-indigo-600 font-semibold transition-colors duration-300"
              >
                {link.name}
              </a>
            ))}
            <a
              href="#download"
              className="bg-indigo-600 hover:bg-indigo-700 text-white px-5 lg:px-6 py-2 sm:py-2.5 rounded-full font-bold transition-all shadow-lg shadow-indigo-500/30 hover:-translate-y-0.5 active:scale-95"
            >
              获取软件
            </a>
          </div>

          <div className="md:hidden">
            <button onClick={() => setMobileMenuOpen(!mobileMenuOpen)} className="p-2 text-slate-600 hover:bg-slate-100 rounded-lg transition">
              {mobileMenuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
            </button>
          </div>
        </div>
      </div>

      {/* 移动端菜单 */}
      {mobileMenuOpen && (
        <div className="md:hidden bg-white/95 backdrop-blur-2xl border-b border-slate-200 shadow-xl absolute w-full transition-all">
          <div className="px-4 pt-2 pb-6 space-y-2">
            {navLinks.map((link) => (
              <a
                key={link.name}
                href={link.href}
                onClick={() => setMobileMenuOpen(false)}
                className="block px-4 py-3 text-base font-bold text-slate-700 hover:bg-indigo-50 hover:text-indigo-600 rounded-xl transition"
              >
                {link.name}
              </a>
            ))}
            <div className="pt-4 pb-2 px-2">
              <a
                href="#download"
                onClick={() => setMobileMenuOpen(false)}
                className="block w-full text-center bg-indigo-600 text-white py-3.5 rounded-xl font-bold shadow-lg shadow-indigo-500/20"
              >
                立即下载
              </a>
            </div>
          </div>
        </div>
      )}
    </nav>
  );
};

// --- 子组件: Hero 区域 ---
const Hero = () => {
  return (
    <section className="relative pt-28 pb-16 sm:pt-36 sm:pb-20 lg:pt-52 lg:pb-40 overflow-hidden px-4">
      <div className="max-w-7xl mx-auto relative z-10 text-center">
        <div className="inline-flex items-center gap-2 px-3 py-1.5 sm:px-4 sm:py-2 rounded-full bg-indigo-50 border border-indigo-100 text-indigo-700 text-xs sm:text-sm font-bold mb-6 sm:mb-8 animate-bounce-subtle">
          <span className="relative flex h-2 w-2">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-indigo-400 opacity-75"></span>
            <span className="relative inline-flex rounded-full h-2 w-2 bg-indigo-500"></span>
          </span>
          Cloudflare 边缘网络实时数据同步
        </div>

        {/* 标题适配移动端尺寸 */}
        <h1 className="text-4xl sm:text-5xl md:text-7xl lg:text-8xl font-black tracking-tighter mb-6 sm:mb-8 leading-[1.15] text-slate-900">
          多端协同，<br className="sm:hidden" />
          <span className="bg-clip-text text-transparent bg-gradient-to-r from-indigo-600 via-purple-600 to-pink-500">
            极致效率
          </span>
        </h1>

        <p className="text-lg sm:text-xl md:text-2xl text-slate-500 max-w-3xl mx-auto mb-10 sm:mb-12 leading-relaxed px-2">
          首创 <strong>C++ 原生桌面微件</strong> 与 <strong>Flutter 沉浸式移动端</strong> 深度联动架构。
          KB 级极简运行，MB 级丰富交互，数据通过 D1 数据库毫秒级分发。
        </p>

        <div className="flex flex-col sm:flex-row justify-center gap-4 sm:gap-6 w-full max-w-md sm:max-w-none mx-auto">
          <a href="#download" className="group flex items-center justify-center gap-3 bg-slate-900 text-white px-8 py-4 sm:px-10 sm:py-5 rounded-2xl text-base sm:text-lg font-bold hover:bg-slate-800 transition-all shadow-xl hover:shadow-indigo-500/20 hover:-translate-y-1 w-full sm:w-auto">
            <Download className="w-5 h-5 sm:w-6 sm:h-6 group-hover:animate-pulse" /> 立即下载
          </a>
          <a href="https://github.com/Junpgle/CountdownTodo" target="_blank" rel="noreferrer" className="flex items-center justify-center gap-3 bg-white text-slate-700 border border-slate-200 px-8 py-4 sm:px-10 sm:py-5 rounded-2xl text-base sm:text-lg font-bold hover:bg-slate-50 transition-all hover:-translate-y-1 shadow-sm w-full sm:w-auto">
            <Github className="w-5 h-5 sm:w-6 sm:h-6" /> 开源仓库
          </a>
        </div>

        {/* 数据展示，适配移动端为两行两列 */}
        <div className="mt-16 sm:mt-20 grid grid-cols-2 md:grid-cols-4 gap-y-8 gap-x-4 max-w-4xl mx-auto opacity-80 px-4">
           <div className="flex flex-col items-center">
              <span className="text-2xl sm:text-3xl font-bold text-slate-800 tracking-tighter">0.1s</span>
              <span className="text-xs sm:text-sm text-slate-400 font-medium mt-1">同步延迟</span>
           </div>
           <div className="flex flex-col items-center border-l border-slate-200">
              <span className="text-2xl sm:text-3xl font-bold text-slate-800 tracking-tighter">8.4MB</span>
              <span className="text-xs sm:text-sm text-slate-400 font-medium mt-1">桌面占用</span>
           </div>
           <div className="flex flex-col items-center md:border-l border-slate-200 pt-6 md:pt-0 border-t md:border-t-0">
              <span className="text-2xl sm:text-3xl font-bold text-slate-800 tracking-tighter">100%</span>
              <span className="text-xs sm:text-sm text-slate-400 font-medium mt-1">原生性能</span>
           </div>
           <div className="flex flex-col items-center border-l border-slate-200 pt-6 md:pt-0 border-t md:border-t-0">
              <span className="text-2xl sm:text-3xl font-bold text-slate-800 tracking-tighter">Serverless</span>
              <span className="text-xs sm:text-sm text-slate-400 font-medium mt-1">后端架构</span>
           </div>
        </div>
      </div>

      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-full h-full -z-10 pointer-events-none overflow-hidden">
        <div className="absolute top-[10%] left-[5%] w-64 h-64 sm:w-96 h-96 bg-indigo-400/20 rounded-full blur-[80px] sm:blur-[100px] animate-pulse"></div>
        <div className="absolute bottom-[20%] right-[5%] w-64 h-64 sm:w-96 sm:h-96 bg-purple-400/20 rounded-full blur-[80px] sm:blur-[100px] animate-pulse delay-1000"></div>
        <div className="absolute inset-0 opacity-[0.03] pointer-events-none" style={{ backgroundImage: 'radial-gradient(#000 1px, transparent 1px)', backgroundSize: '30px 30px' }}></div>
      </div>
    </section>
  );
};

// --- 子组件: 核心特性网格 ---
const Features = () => {
  const features = [
    {
      title: "桌面端 (Win32)",
      desc: "基于 C++17 原生开发，拒绝臃肿。Layered Window 透明磨砂渲染，极致轻量，常驻桌面却不打扰。",
      icon: <Monitor className="w-6 h-6 sm:w-7 sm:h-7 text-blue-600" />,
      color: "bg-blue-50 border-blue-100"
    },
    {
      title: "移动端 (Flutter)",
      desc: "Material 3 规范打造。集成屏幕时间统计、三级应用分类分析、动态必应壁纸，每一处交互都丝滑顺手。",
      icon: <Smartphone className="w-6 h-6 sm:w-7 sm:h-7 text-purple-600" />,
      color: "bg-purple-50 border-purple-100"
    },
    {
      title: "数据同步 (D1)",
      desc: "基于 Cloudflare D1 分布式数据库。独创 LWW 冲突解决算法，支持跨端待办、倒计时毫秒级即时同步。",
      icon: <CloudLightning className="w-6 h-6 sm:w-7 sm:h-7 text-amber-600" />,
      color: "bg-amber-50 border-amber-100"
    }
  ];

  return (
    <section id="features" className="py-16 sm:py-24 bg-white relative">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="text-center max-w-3xl mx-auto mb-12 sm:mb-20 px-2">
          <h2 className="text-3xl sm:text-4xl font-bold text-slate-900 mb-4 tracking-tight">差异化架构，重塑生产力</h2>
          <p className="text-base sm:text-lg text-slate-500">我们坚信：桌面端应追求极致克制，移动端应追求丰富表达，云端应追求稳定可靠。</p>
        </div>

        <div className="grid md:grid-cols-3 gap-6 sm:gap-10">
          {features.map((f, i) => (
            <div key={i} className="p-8 sm:p-10 rounded-[2rem] bg-slate-50 border border-slate-100 hover:bg-white hover:shadow-2xl hover:shadow-indigo-500/10 transition-all duration-500 group">
              <div className={`w-14 h-14 sm:w-16 sm:h-16 ${f.color} border rounded-2xl flex items-center justify-center mb-6 sm:mb-8 group-hover:scale-110 group-hover:rotate-3 transition duration-300 shadow-sm`}>
                {f.icon}
              </div>
              <h3 className="text-xl sm:text-2xl font-bold mb-3 sm:mb-4 text-slate-900">{f.title}</h3>
              <p className="text-slate-500 leading-relaxed text-sm sm:text-base">{f.desc}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};

// --- 子组件: 平台展示区域 (Windows) ---
const WindowsShowcase = () => {
  return (
    <section id="desktop" className="py-16 sm:py-24 bg-slate-900 text-white relative overflow-hidden">
      <div className="absolute top-0 left-0 p-4 sm:p-10 opacity-10 pointer-events-none font-mono text-[10px] sm:text-xs leading-loose text-blue-400">
        #include "common.h"<br/>
        using namespace Gdiplus;<br/>
        RenderWidget() &#123;<br/>
        &nbsp;&nbsp;UpdateLayeredWindow(g_hWidgetWnd, hdcScreen...);<br/>
        &#125;
      </div>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        <div className="flex flex-col lg:flex-row items-center gap-12 sm:gap-20">
          <div className="lg:w-1/2 w-full">
            <div className="inline-flex items-center gap-2 px-3 py-1 bg-blue-500/20 border border-blue-500/30 text-blue-400 rounded-lg text-[10px] sm:text-xs font-bold uppercase tracking-widest mb-4 sm:mb-6">
              <Cpu className="w-3 h-3 sm:w-4 sm:h-4" /> Native Performance
            </div>
            <h2 className="text-3xl sm:text-4xl md:text-5xl font-bold mb-6 sm:mb-8 leading-tight">
              Windows Lite <br className="hidden sm:block"/>
              <span className="text-slate-400 font-medium italic sm:ml-0 ml-2">零感桌面组件</span>
            </h2>
            <div className="space-y-6 sm:space-y-8">
              {[
                { t: "Win32 原生渲染", d: "拒绝 Electron。基于 C++17 与 GDI+ 矢量绘图，支持像素级 Alpha 透明，完美贴合系统桌面。" },
                { t: "自动更新机制", d: "内置版本嗅探线程。静默检查 GitHub Manifest，一键直连下载，保持版本始终最新。" },
                { t: "DPAPI 加密存储", d: "使用 Windows 账户级别加密技术存储用户 Token，从系统底层守护你的隐私安全。" }
              ].map((item, i) => (
                <div key={i} className="flex gap-3 sm:gap-4 group">
                  <div className="mt-1">
                    <CheckCircle2 className="w-5 h-5 sm:w-6 sm:h-6 text-blue-400" />
                  </div>
                  <div>
                    <h4 className="text-lg sm:text-xl font-bold mb-1 sm:mb-2 group-hover:text-blue-400 transition-colors">{item.t}</h4>
                    <p className="text-sm sm:text-base text-slate-400 leading-relaxed">{item.d}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="lg:w-1/2 w-full relative mt-8 lg:mt-0">
             <div className="absolute -inset-2 bg-gradient-to-r from-blue-600 to-indigo-600 rounded-[2rem] blur-xl opacity-20 sm:opacity-30 animate-pulse"></div>
             <div className="relative bg-slate-800 rounded-[1.5rem] p-3 sm:p-4 border border-slate-700 shadow-2xl overflow-hidden group">
                <div className="flex items-center justify-between px-3 sm:px-4 py-2 border-b border-slate-700 mb-2 sm:mb-0">
                   <div className="flex gap-1.5 sm:gap-2">
                      <div className="w-2.5 h-2.5 sm:w-3 sm:h-3 rounded-full bg-red-500"></div>
                      <div className="w-2.5 h-2.5 sm:w-3 sm:h-3 rounded-full bg-yellow-500"></div>
                      <div className="w-2.5 h-2.5 sm:w-3 sm:h-3 rounded-full bg-green-500"></div>
                   </div>
                   <span className="text-[10px] font-mono text-slate-500">MathQuizWidget.exe</span>
                </div>
                <div className="aspect-[3/4] sm:aspect-[4/5] bg-slate-900 rounded-xl sm:rounded-b-xl flex items-center justify-center relative overflow-hidden">
                   <div className="absolute inset-0 bg-blue-500/5 flex flex-col items-center justify-center gap-4">
                      <Layers className="w-12 h-12 sm:w-20 sm:h-20 text-blue-500/20" />
                      <p className="text-slate-500 text-xs sm:text-sm font-medium">预览图载入中...</p>
                   </div>
                   <img
                    src="/1.jpg"
                    alt="桌面端预览"
                    className="relative z-10 max-w-[90%] sm:max-w-[85%] rounded-lg shadow-2xl border border-white/10 group-hover:scale-105 transition-transform duration-700"
                    onError={(e) => e.target.style.display='none'}
                   />
                </div>
             </div>
             <div className="absolute -bottom-4 -right-4 sm:-bottom-6 sm:-right-6 bg-blue-600 p-4 sm:p-6 rounded-2xl shadow-xl animate-bounce-subtle">
                <MousePointer2 className="w-6 h-6 sm:w-8 sm:h-8 text-white mb-1 sm:mb-2" />
                <div className="text-[10px] sm:text-xs font-bold text-blue-100 uppercase tracking-tighter">Right Click</div>
                <div className="text-white text-xs sm:text-sm font-bold">手动检查更新</div>
             </div>
          </div>
        </div>
      </div>
    </section>
  );
};

// --- 子组件: 移动端展示区域 (Android) ---
const AndroidShowcase = () => {
  return (
    <section id="mobile" className="py-16 sm:py-24 bg-white overflow-hidden">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col lg:flex-row-reverse items-center gap-16 sm:gap-20">
          <div className="lg:w-1/2 w-full">
            <div className="inline-flex items-center gap-2 px-3 py-1 bg-purple-50 border border-purple-200 text-purple-700 rounded-lg text-[10px] sm:text-xs font-bold uppercase tracking-widest mb-4 sm:mb-6">
              <Smartphone className="w-3 h-3 sm:w-4 sm:h-4" /> Flutter Material 3
            </div>
            <h2 className="text-3xl sm:text-4xl md:text-5xl font-bold mb-6 sm:mb-8 leading-tight text-slate-900">
              Android Pro <br className="hidden sm:block"/>
              <span className="text-indigo-600 font-medium italic sm:ml-0 ml-2">沉浸式数据管家</span>
            </h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 sm:gap-6">
              {[
                { i: <BellRing className="w-5 h-5 sm:w-6 sm:h-6" />, t: "智能交互通知", d: "原生 Android 线程监听，实时更新答题进度与待办摘要。" },
                { i: <ImageIcon className="w-5 h-5 sm:w-6 sm:h-6" />, t: "全自动壁纸", d: "打通 Bing & GitHub 壁纸库，每日启动自动刷新桌面背景。" },
                { i: <Clock className="w-5 h-5 sm:w-6 sm:h-6" />, t: "桌面微件控制", d: "支持桌面小部件快速查看和操作，无需打开应用。" }
              ].map((card, i) => (
                <div key={i} className="p-5 sm:p-6 rounded-3xl bg-slate-50 border border-slate-100 hover:border-indigo-200 transition-all group hover:bg-white hover:shadow-lg">
                   <div className="w-10 h-10 sm:w-12 sm:h-12 bg-white rounded-xl shadow-sm border border-slate-100 text-indigo-600 mb-4 flex items-center justify-center group-hover:scale-110 group-hover:bg-indigo-600 group-hover:text-white transition duration-300">
                     {card.i}
                   </div>
                   <h5 className="font-bold text-slate-900 mb-2 sm:text-base text-sm">{card.t}</h5>
                   <p className="text-xs sm:text-sm text-slate-500 leading-relaxed">{card.d}</p>
                </div>
              ))}
            </div>
          </div>

          <div className="lg:w-1/2 w-full flex justify-center relative mt-8 lg:mt-0">
            {/* 手机外壳：安卓打孔屏设计 */}
            <div className="relative w-[260px] sm:w-[300px] aspect-[9/19.5] bg-slate-900 rounded-[3rem] sm:rounded-[3.5rem] border-[8px] sm:border-[10px] border-slate-900 shadow-[0_40px_80px_-20px_rgba(0,0,0,0.4)] overflow-hidden shrink-0">
               {/* 居中打孔摄像头 */}
               <div className="absolute top-3 sm:top-4 left-1/2 -translate-x-1/2 w-3 h-3 sm:w-4 sm:h-4 bg-black rounded-full z-20 shadow-inner"></div>
               <div className="absolute inset-0 bg-white">
                  <img
                    src="/2.jpg"
                    alt="App 预览图"
                    className="w-full h-full object-cover rounded-[2.5rem] sm:rounded-[2.8rem]"
                    onError={(e) => {
                      e.target.src = "https://images.unsplash.com/photo-1512941937669-90a1b58e7e9c?auto=format&fit=crop&q=80&w=800";
                    }}
                  />
               </div>
            </div>

            {/* 装饰标签 */}
            <div className="absolute top-1/4 -left-2 sm:-left-6 bg-indigo-600 text-white py-2 px-4 sm:p-4 rounded-xl sm:rounded-2xl shadow-2xl rotate-[-12deg] z-30">
               <span className="font-bold text-xs sm:text-sm">Android 8.0+</span>
            </div>
            <div className="absolute bottom-1/4 -right-4 sm:-right-8 bg-pink-500 text-white py-2 px-4 sm:p-4 rounded-xl sm:rounded-2xl shadow-2xl rotate-[6deg] z-30">
               <span className="font-bold text-xs sm:text-sm">Material 3</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};

// --- 子组件: 屏幕时间看板 (双图手机并排错落布局) ---
const ScreenTimeShowcase = () => {
  return (
    <section id="screentime" className="py-16 sm:py-24 bg-slate-50 border-y border-slate-200 overflow-hidden">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="text-center max-w-3xl mx-auto mb-12 sm:mb-16 px-2">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 bg-emerald-100 border border-emerald-200 text-emerald-700 rounded-lg text-[10px] sm:text-xs font-bold uppercase tracking-widest mb-4 sm:mb-6">
            <Activity className="w-3 h-3 sm:w-4 sm:h-4" /> 深度功能体验
          </div>
          <h2 className="text-3xl sm:text-4xl font-bold text-slate-900 mb-4 sm:mb-6 tracking-tight">全方位多端屏幕时间分析</h2>
          <p className="text-base sm:text-lg text-slate-500 leading-relaxed">
            不再局限于单设备统计。我们将手机、平板和电脑的使用时间全面整合，配合丰富的统计图表，为您提供最真实的数字化生活全貌。
          </p>
        </div>

        <div className="flex flex-col lg:flex-row items-center justify-between gap-12 sm:gap-16">
          <div className="lg:w-5/12 w-full space-y-6 sm:space-y-8 order-2 lg:order-1">
            <div className="bg-white p-6 sm:p-8 rounded-3xl shadow-sm border border-slate-100 hover:shadow-lg transition-shadow">
              <div className="w-12 h-12 bg-emerald-50 rounded-2xl flex items-center justify-center mb-4 sm:mb-5">
                <PieChart className="w-6 h-6 sm:w-7 sm:h-7 text-emerald-600" />
              </div>
              <h3 className="text-xl sm:text-2xl font-bold text-slate-900 mb-2 sm:mb-3">多级可视化图表</h3>
              <p className="text-sm sm:text-base text-slate-600 leading-relaxed">
                引入纯手工绘制的近七日趋势柱状图与多维度分类饼图。二级界面深度重构，通过 3x2 宫格直观展示社交通讯、学习办公等分类占比。
              </p>
            </div>

            <div className="bg-white p-6 sm:p-8 rounded-3xl shadow-sm border border-slate-100 hover:shadow-lg transition-shadow">
              <div className="w-12 h-12 bg-teal-50 rounded-2xl flex items-center justify-center mb-4 sm:mb-5">
                <RefreshCw className="w-6 h-6 sm:w-7 sm:h-7 text-teal-600" />
              </div>
              <h3 className="text-xl sm:text-2xl font-bold text-slate-900 mb-2 sm:mb-3">无感异步加载</h3>
              <p className="text-sm sm:text-base text-slate-600 leading-relaxed">
                告别白屏等待。进入看板即刻展示本地缓存数据，后台静默拉取并合并近六日云端历史记录，实现图表的“丝滑秒开”。
              </p>
            </div>
          </div>

          <div className="lg:w-7/12 w-full relative group order-1 lg:order-2 flex justify-center">
            {/* 炫酷背景光晕 */}
            <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-full h-[120%] bg-gradient-to-tr from-emerald-400 to-teal-500 rounded-[3rem] blur-2xl opacity-10 sm:opacity-20 group-hover:opacity-30 transition duration-700 pointer-events-none"></div>

            {/* 双手机模型并排错落布局 */}
            <div className="relative flex justify-center items-center gap-4 sm:gap-6 md:gap-8 w-full max-w-[500px]">
               {/* 手机模型 1 */}
               <div className="relative w-[150px] sm:w-[200px] md:w-[220px] aspect-[9/19.5] bg-slate-900 rounded-[2rem] sm:rounded-[2.5rem] border-[6px] sm:border-[8px] border-slate-900 shadow-xl overflow-hidden shrink-0 transform group-hover:-translate-y-2 transition-transform duration-500">
                   {/* 居中打孔 */}
                   <div className="absolute top-2.5 sm:top-3 left-1/2 -translate-x-1/2 w-2.5 h-2.5 sm:w-3 sm:h-3 bg-black rounded-full z-20 shadow-inner"></div>
                   <div className="absolute inset-0 bg-white">
                       <img
                         src="/3.jpg"
                         alt="屏幕时间统计界面1"
                         className="w-full h-full object-cover rounded-[1.5rem] sm:rounded-[2rem]"
                         onError={(e) => e.target.style.display='none'}
                       />
                   </div>
               </div>

               {/* 手机模型 2 (位置偏下) */}
               <div className="relative w-[150px] sm:w-[200px] md:w-[220px] aspect-[9/19.5] bg-slate-900 rounded-[2rem] sm:rounded-[2.5rem] border-[6px] sm:border-[8px] border-slate-900 shadow-xl overflow-hidden shrink-0 mt-16 sm:mt-24 transform group-hover:translate-y-2 transition-transform duration-500">
                   {/* 居中打孔 */}
                   <div className="absolute top-2.5 sm:top-3 left-1/2 -translate-x-1/2 w-2.5 h-2.5 sm:w-3 sm:h-3 bg-black rounded-full z-20 shadow-inner"></div>
                   <div className="absolute inset-0 bg-white">
                       <img
                         src="/4.jpg"
                         alt="屏幕时间统计界面2"
                         className="w-full h-full object-cover rounded-[1.5rem] sm:rounded-[2rem]"
                         onError={(e) => e.target.style.display='none'}
                       />
                   </div>
               </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};

// --- 子组件: 数据看板板块 ---
const AnalyticsPreview = () => {
  return (
    <section id="analytics" className="py-16 sm:py-24 bg-indigo-50/50">
      <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
        <h2 className="text-3xl sm:text-4xl font-bold mb-4 sm:mb-6 text-slate-900 tracking-tight">数据聚合，一眼万年</h2>
        <p className="text-base sm:text-lg text-slate-500 mb-10 sm:mb-16 px-2">
          我们将手机、平板、PC 的使用数据通过后端 D1 数据库完美汇聚。<br className="hidden sm:block"/>
          通过内置的分类字典，自动合并多端应用时长记录。
        </p>

        <div className="bg-white p-6 sm:p-10 md:p-12 rounded-[2rem] sm:rounded-[3rem] shadow-xl shadow-indigo-500/5 border border-slate-100 text-left">
          <div className="flex flex-col md:flex-row gap-8 sm:gap-12 items-center">
            <div className="flex-1 space-y-5 sm:space-y-6 w-full">
              <div className="flex items-center gap-3">
                 <div className="w-8 h-8 rounded-full bg-green-100 flex items-center justify-center text-green-600 shrink-0">
                   <Database className="w-4 h-4 sm:w-5 sm:h-5" />
                 </div>
                 <span className="font-bold text-base sm:text-lg text-slate-800">云端字典自动映射</span>
              </div>
              <p className="text-sm sm:text-base text-slate-500 leading-relaxed">
                后端通过 D1 数据库存储 <code className="bg-slate-100 px-1.5 py-0.5 rounded text-sm">app_name_mappings</code> 表。
                无论包名是 <code className="text-indigo-600 font-mono text-sm">com.tencent.mm</code> 还是 <code className="text-indigo-600 font-mono text-sm">Weixin.exe</code>，均会自动归类为“微信”并划入“社交通讯”板块。
              </p>
              <div className="pt-2 sm:pt-4 flex flex-wrap gap-2 sm:gap-3">
                 <div className="bg-slate-100 text-slate-600 px-3 sm:px-4 py-1.5 sm:py-2 rounded-full text-xs sm:text-sm font-bold">影音娱乐</div>
                 <div className="bg-slate-100 text-slate-600 px-3 sm:px-4 py-1.5 sm:py-2 rounded-full text-xs sm:text-sm font-bold">学习办公</div>
                 <div className="bg-slate-100 text-slate-600 px-3 sm:px-4 py-1.5 sm:py-2 rounded-full text-xs sm:text-sm font-bold">系统应用</div>
              </div>
            </div>

            <div className="flex-1 grid grid-cols-2 sm:grid-cols-3 gap-2 sm:gap-3 w-full">
              {[1, 2, 3, 4, 5, 6].map(i => (
                <div key={i} className="aspect-square bg-slate-50 rounded-xl sm:rounded-2xl border border-slate-100 flex flex-col items-center justify-center p-3 sm:p-4 hover:border-indigo-300 transition-colors cursor-default">
                  <div className="w-6 h-6 sm:w-8 sm:h-8 rounded-full bg-white shadow-sm mb-2"></div>
                  <div className="w-10 sm:w-12 h-1.5 sm:h-2 bg-slate-200 rounded-full mb-1"></div>
                  <div className="w-6 sm:w-8 h-1 sm:h-1.5 bg-slate-100 rounded-full"></div>
                </div>
              ))}
              <div className="col-span-2 sm:col-span-3 text-center text-[10px] sm:text-xs text-slate-400 font-bold uppercase tracking-widest mt-2">
                3x2 今日类别分布预览
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};

// --- 子组件: 下载部分 ---
const DownloadSection = ({ androidInfo, windowsInfo }) => {
  return (
    <section id="download" className="py-20 sm:py-32 bg-white text-center relative overflow-hidden">
      <div className="max-w-5xl mx-auto px-4 relative z-10">
        <h2 className="text-3xl sm:text-4xl md:text-5xl font-black mb-4 sm:mb-6 text-slate-900">准备好提升效率了吗？</h2>
        <p className="text-base sm:text-xl text-slate-500 mb-10 sm:mb-16 max-w-2xl mx-auto leading-relaxed px-2">
          选择你的设备平台。所有平台数据基于同一个云端账号实时互通。
        </p>

        <div className="grid md:grid-cols-2 gap-6 sm:gap-8 text-left">
          {/* Windows 卡片 */}
          <div className="group relative p-6 sm:p-8 lg:p-10 bg-slate-50 rounded-3xl sm:rounded-[3rem] border-2 border-transparent hover:border-blue-500 hover:bg-white transition-all duration-500 hover:-translate-y-1 sm:hover:-translate-y-2">
            <div className="flex justify-between items-start mb-6 sm:mb-8">
              <div className="w-14 h-14 sm:w-16 sm:h-16 bg-blue-100 rounded-[1.2rem] sm:rounded-[1.5rem] flex items-center justify-center text-blue-600 group-hover:scale-110 transition duration-500">
                 <Monitor className="w-7 h-7 sm:w-8 sm:h-8" />
              </div>
              {windowsInfo.version && (
                <span className="bg-blue-100 text-blue-600 px-2.5 py-1 sm:px-3 sm:py-1 rounded-full text-[10px] sm:text-xs font-bold tracking-wider uppercase">
                  v{windowsInfo.version}
                </span>
              )}
            </div>
            <h3 className="text-xl sm:text-2xl font-bold text-slate-900 mb-2">Windows Lite</h3>
            <p className="text-slate-500 mb-6 sm:mb-8 text-xs sm:text-sm leading-relaxed min-h-[40px]">
              {windowsInfo.desc || "适用于 Win 10/11 x64 原生高性能编译版本。"}
            </p>
            <a
              href={windowsInfo.url || "https://github.com/Junpgle/CountdownTodo/releases"}
              className="flex items-center justify-center gap-2 sm:gap-3 bg-blue-600 text-white w-full py-3.5 sm:py-4 rounded-xl sm:rounded-2xl font-bold text-base sm:text-lg shadow-lg shadow-blue-500/30 hover:bg-blue-700 transition"
            >
              获取下载 <ChevronRight className="w-4 h-4 sm:w-5 sm:h-5" />
            </a>
          </div>

          {/* Android 卡片 */}
          <div className="group relative p-6 sm:p-8 lg:p-10 bg-slate-50 rounded-3xl sm:rounded-[3rem] border-2 border-transparent hover:border-indigo-500 hover:bg-white transition-all duration-500 hover:-translate-y-1 sm:hover:-translate-y-2">
            <div className="flex justify-between items-start mb-6 sm:mb-8">
              <div className="w-14 h-14 sm:w-16 sm:h-16 bg-indigo-100 rounded-[1.2rem] sm:rounded-[1.5rem] flex items-center justify-center text-indigo-600 group-hover:scale-110 transition duration-500">
                 <Smartphone className="w-7 h-7 sm:w-8 sm:h-8" />
              </div>
              {androidInfo.version && (
                <span className="bg-indigo-100 text-indigo-600 px-2.5 py-1 sm:px-3 sm:py-1 rounded-full text-[10px] sm:text-xs font-bold tracking-wider uppercase">
                  v{androidInfo.version}
                </span>
              )}
            </div>
            <h3 className="text-xl sm:text-2xl font-bold text-slate-900 mb-2">Android Pro</h3>
            <p className="text-slate-500 mb-6 sm:mb-8 text-xs sm:text-sm leading-relaxed min-h-[40px]">
              {androidInfo.desc || "支持 Android 8.0+ APK 完整功能体验版。"}
            </p>
            <a
              href={androidInfo.url || "https://github.com/Junpgle/CountdownTodo/releases"}
              className="flex items-center justify-center gap-2 sm:gap-3 bg-indigo-600 text-white w-full py-3.5 sm:py-4 rounded-xl sm:rounded-2xl font-bold text-base sm:text-lg shadow-lg shadow-indigo-500/30 hover:bg-indigo-700 transition"
            >
              立即安装 <ChevronRight className="w-4 h-4 sm:w-5 sm:h-5" />
            </a>
          </div>
        </div>

        <p className="mt-12 sm:mt-16 text-slate-400 text-xs sm:text-sm font-medium">
          * 最新版本由 GitHub 公告文件自动解析提供。
        </p>
      </div>

      <div className="absolute bottom-0 left-0 w-48 h-48 sm:w-64 sm:h-64 bg-indigo-100/40 rounded-full blur-[60px] sm:blur-[80px] -z-10"></div>
    </section>
  );
};

// --- 主组件: App ---
const App = () => {
  const [androidInfo, setAndroidInfo] = useState({ version: '', url: '', desc: '' });
  const [windowsInfo, setWindowsInfo] = useState({ version: '', url: '', desc: '' });

  useEffect(() => {
    const fetchAndroid = async () => {
      try {
        const res = await fetch("https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json");
        const data = await res.json();
        setAndroidInfo({
          version: data.version_name,
          url: data.update_info.full_package_url,
          desc: data.update_info.description
        });
      } catch (e) {
        console.error("Failed to fetch Android manifest", e);
      }
    };

    const fetchWindows = async () => {
      try {
        const res = await fetch("https://raw.githubusercontent.com/Junpgle/CountDownTodoLite/refs/heads/master/update_manifest.json");
        const data = await res.json();
        setWindowsInfo({
          version: data.version_name,
          url: data.update_info.full_package_url,
          desc: data.update_info.description
        });
      } catch (e) {
        console.error("Failed to fetch Windows manifest", e);
      }
    };

    fetchAndroid();
    fetchWindows();
  }, []);

  return (
    <div className="bg-white min-h-screen selection:bg-indigo-600 selection:text-white font-sans">
      <Navbar />
      <Hero />
      <Features />
      <WindowsShowcase />
      <AndroidShowcase />
      <ScreenTimeShowcase />
      <AnalyticsPreview />
      <DownloadSection androidInfo={androidInfo} windowsInfo={windowsInfo} />

      <footer className="bg-slate-50 py-12 sm:py-16 border-t border-slate-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex flex-col md:flex-row justify-between items-center gap-6 sm:gap-8">
            <div className="text-center md:text-left">
              <div className="flex items-center gap-2 mb-3 sm:mb-4 justify-center md:justify-start">
                <div className="bg-indigo-600 p-1.5 rounded-md">
                  <Layers className="text-white w-4 h-4 sm:w-5 sm:h-5" />
                </div>
                <span className="font-bold text-lg sm:text-xl text-slate-800">CountDownTodo</span>
              </div>
              <p className="text-slate-400 text-xs sm:text-sm max-w-[260px] sm:max-w-xs leading-relaxed mx-auto md:mx-0">
                致力于打造跨设备协同的个人数字化生存效率方案。
              </p>
            </div>

            <div className="flex flex-col items-center md:items-end gap-4 sm:gap-6">
              <div className="flex space-x-6 sm:space-x-8">
                <a href="https://github.com/Junpgle" target="_blank" rel="noreferrer" className="text-slate-400 hover:text-slate-600 transition transform hover:scale-110">
                  <Github className="w-6 h-6 sm:w-8 sm:h-8" />
                </a>
              </div>
              <p className="text-slate-400 text-[10px] sm:text-xs font-bold uppercase tracking-widest">
                © 2026 JUNPGLE. ALL RIGHTS RESERVED.
              </p>
            </div>
          </div>
        </div>
      </footer>

      <style dangerouslySetInnerHTML={{ __html: `
        @keyframes bounce-subtle {
          0%, 100% { transform: translateY(0); }
          50% { transform: translateY(-5px); }
        }
        .animate-bounce-subtle {
          animation: bounce-subtle 3s ease-in-out infinite;
        }
        html {
          scroll-behavior: smooth;
        }
      `}} />
    </div>
  );
};

export default App;