import { useState, useEffect } from 'react';
import {
  Layers,
  Monitor,
  Smartphone,
  CloudLightning,
  Download,
  Github,
  CheckCircle2,
  Menu,
  X,
  ChevronRight,
  Database,
  Cpu,
  PieChart,
  Activity,
  Tablet as TabletIcon
} from 'lucide-react';

// --- 类型定义 ---
interface AppInfo {
  version: string;
  url: string;
  desc: string;
}

/* =========================
   设备 Frame 组件（彻底修复尺寸与塌陷问题）
   移除了写死的尺寸，完全基于外层百分比缩放
========================= */

// 手机外框
const MobileFrame = ({ src, className = "" }: { src: string; className?: string }) => (
  <div
    className={`relative w-full aspect-[9/19.5] bg-slate-900 rounded-[2rem] md:rounded-[2.5rem] border-[6px] md:border-[10px] border-slate-900 shadow-2xl overflow-hidden ${className}`}
  >
    <div className="absolute top-3 md:top-4 left-1/2 -translate-x-1/2 w-3 md:w-4 h-3 md:h-4 bg-black rounded-full z-20 shadow-inner" />
    <div className="absolute inset-0 bg-white">
      <img
        src={src}
        alt="Mobile App"
        className="w-full h-full object-cover"
        onError={(e) => {
          e.currentTarget.src =
            'https://images.unsplash.com/photo-1512941937669-90a1b58e7e9c?auto=format&fit=crop&q=80&w=800';
        }}
      />
    </div>
  </div>
);

// 平板外框 (比例 3:2)
const TabletFrame = ({ src, className = "" }: { src: string; className?: string }) => (
  <div
    className={`relative w-full aspect-[3/2] bg-slate-800 rounded-[1.5rem] md:rounded-[2rem] border-[6px] md:border-[12px] border-slate-800 shadow-2xl overflow-hidden ${className}`}
  >
    <div className="absolute top-1/2 left-2 md:left-3 -translate-y-1/2 w-2 md:w-3 h-2 md:h-3 bg-black rounded-full z-20" />
    <div className="absolute inset-0 bg-white">
      <img
        src={src}
        alt="Tablet App"
        className="w-full h-full object-cover"
        onError={(e) => {
          e.currentTarget.src =
            'https://images.unsplash.com/photo-1544244015-0df4b3ffc6b0?auto=format&fit=crop&q=80&w=800';
        }}
      />
    </div>
  </div>
);

// 显示器外框
const MonitorFrame = ({ src, className = "" }: { src: string; className?: string }) => (
  <div className={`flex flex-col items-center w-full ${className}`}>
    <div className="relative w-full aspect-[16/10] bg-slate-800 rounded-t-[1.5rem] md:rounded-t-[2.5rem] border-[8px] md:border-[14px] border-slate-800 shadow-2xl overflow-hidden">
      <div className="absolute inset-0 bg-white">
        <img
          src={src}
          alt="Desktop App"
          className="w-full h-full object-cover"
          onError={(e) => {
            e.currentTarget.src =
              'https://images.unsplash.com/photo-1498050108023-c5249f4df085?auto=format&fit=crop&q=80&w=800';
          }}
        />
      </div>
    </div>
    <div className="w-1/3 h-6 md:h-10 bg-slate-700 relative">
      <div className="absolute bottom-0 left-1/2 -translate-x-1/2 w-[200%] md:w-72 h-3 md:h-4 bg-slate-900 rounded-t-xl md:rounded-t-2xl" />
    </div>
  </div>
);

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
              <a key={link.name} href={link.href} className="text-slate-600 hover:text-indigo-600 font-semibold transition-colors duration-300">{link.name}</a>
            ))}
            <a href="#download" className="bg-indigo-600 hover:bg-indigo-700 text-white px-5 lg:px-6 py-2 sm:py-2.5 rounded-full font-bold transition-all shadow-lg shadow-indigo-500/30 hover:-translate-y-0.5 active:scale-95">获取软件</a>
          </div>

          <div className="md:hidden">
            <button onClick={() => setMobileMenuOpen(!mobileMenuOpen)} className="p-2 text-slate-600 hover:bg-slate-100 rounded-lg transition">
              {mobileMenuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
            </button>
          </div>
        </div>
      </div>
      {mobileMenuOpen && (
        <div className="md:hidden bg-white/95 backdrop-blur-2xl border-b border-slate-200 shadow-xl absolute w-full transition-all">
          <div className="px-4 pt-2 pb-6 space-y-2">
            {navLinks.map((link) => (
              <a key={link.name} href={link.href} onClick={() => setMobileMenuOpen(false)} className="block px-4 py-3 text-base font-bold text-slate-700 hover:bg-indigo-50 hover:text-indigo-600 rounded-xl transition">{link.name}</a>
            ))}
            <div className="pt-4 pb-2 px-2">
              <a href="#download" onClick={() => setMobileMenuOpen(false)} className="block w-full text-center bg-indigo-600 text-white py-3.5 rounded-xl font-bold shadow-lg shadow-indigo-500/20">立即下载</a>
            </div>
          </div>
        </div>
      )}
    </nav>
  );
};

// --- 子组件: Hero 区域 ---
const Hero = () => (
  <section className="relative pt-28 pb-16 sm:pt-36 sm:pb-20 lg:pt-52 lg:pb-40 overflow-hidden px-4">
    <div className="max-w-7xl mx-auto relative z-10 text-center">
      <div className="inline-flex items-center gap-2 px-3 py-1.5 sm:px-4 sm:py-2 rounded-full bg-indigo-50 border border-indigo-100 text-indigo-700 text-xs sm:text-sm font-bold mb-6 sm:mb-8 animate-bounce-subtle">
        <CloudLightning className="w-4 h-4 text-indigo-500" />
        Cloudflare D1 边缘数据库实时同步支持
      </div>
      <h1 className="text-4xl sm:text-5xl md:text-7xl lg:text-8xl font-black tracking-tighter mb-6 sm:mb-8 leading-[1.15] text-slate-900">
        多端协同，<br className="sm:hidden" />
        <span className="bg-clip-text text-transparent bg-gradient-to-r from-indigo-600 via-purple-600 to-pink-500">极致效率</span>
      </h1>
      <p className="text-lg sm:text-xl md:text-2xl text-slate-500 max-w-3xl mx-auto mb-10 sm:mb-12 leading-relaxed px-2">
        原生 C++ 桌面组件与 Flutter 移动端深度联动。KB 级极简运行，数据毫秒级同步。
      </p>
      <div className="flex flex-col sm:flex-row justify-center gap-4 sm:gap-6 w-full max-w-md sm:max-w-none mx-auto">
        <a href="#download" className="group flex items-center justify-center gap-3 bg-slate-900 text-white px-8 py-4 sm:px-10 sm:py-5 rounded-2xl text-base sm:text-lg font-bold hover:bg-slate-800 transition-all shadow-xl hover:-translate-y-1 w-full sm:w-auto">
          <Download className="w-5 h-5 group-hover:animate-pulse" /> 立即下载
        </a>
        <a href="https://github.com/Junpgle/CountdownTodo" target="_blank" rel="noreferrer" className="flex items-center justify-center gap-3 bg-white text-slate-700 border border-slate-200 px-8 py-4 sm:px-10 sm:py-5 rounded-2xl text-base sm:text-lg font-bold hover:bg-slate-50 transition-all hover:-translate-y-1 shadow-sm w-full sm:w-auto">
          <Github className="w-5 h-5" /> 开源仓库
        </a>
      </div>
    </div>
    <div className="absolute top-0 left-1/2 -translate-x-1/2 w-full h-full -z-10 pointer-events-none opacity-[0.03]" style={{ backgroundImage: 'radial-gradient(#000 1px, transparent 1px)', backgroundSize: '30px 30px' }}></div>
  </section>
);

// --- 子组件: 核心特性网格 ---
const Features = () => {
  const features = [
    { title: "桌面端 (Win32)", desc: "C++17 原生开发。Layered Window 透明渲染，极低占用，常驻不打扰。", icon: <Monitor className="w-6 h-6" />, color: "bg-blue-50 text-blue-600" },
    { title: "移动端 (Flutter)", desc: "Material 3 规范。沉浸式交互，三级应用分类分析，动态壁纸切换。", icon: <Smartphone className="w-6 h-6" />, color: "bg-purple-50 text-purple-600" },
    { title: "云端同步 (D1)", desc: "分布式数据库架构。多端数据毫秒级分发，支持跨设备待办实时更新。", icon: <CloudLightning className="w-6 h-6" />, color: "bg-amber-50 text-amber-600" }
  ];
  return (
    <section id="features" className="py-16 sm:py-24 bg-white">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="grid md:grid-cols-3 gap-8">
          {features.map((f, i) => (
            <div key={i} className="p-10 rounded-[2.5rem] bg-slate-50 hover:bg-white hover:shadow-xl transition-all duration-500 group border border-slate-100">
              <div className={`w-14 h-14 ${f.color} rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 transition`}>{f.icon}</div>
              <h3 className="text-2xl font-bold mb-4 text-slate-900">{f.title}</h3>
              <p className="text-slate-500 leading-relaxed text-base">{f.desc}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};

// --- 子组件: Windows 展示 (6.jpg 主显 & 1.jpg 悬浮小部件) ---
const WindowsShowcase = () => (
  <section id="desktop" className="py-24 sm:py-40 bg-slate-900 text-white relative overflow-hidden">
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10 text-center">
      <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-blue-500/20 text-blue-400 rounded-lg text-sm font-bold uppercase tracking-widest mb-8">
        <Monitor className="w-5 h-5" /> Native Desktop
      </div>
      <h2 className="text-4xl sm:text-6xl font-black mb-10 tracking-tight text-white text-center">Windows Lite 极致轻量桌面</h2>
      <p className="text-slate-400 text-lg max-w-3xl mx-auto mb-20 leading-relaxed text-center">
        拒绝臃肿。基于 C++17 与 GDI+ 渲染，独创的悬浮小部件设计，让效率在桌面每一寸像素中自由流淌。
      </p>

      <div className="flex justify-center relative group w-full max-w-[900px] mx-auto pb-20 px-2 sm:px-6">
        <div className="absolute -inset-20 bg-blue-500/10 blur-[120px] rounded-full pointer-events-none"></div>

        {/* 6.jpg 作为主显示器 */}
        <MonitorFrame src="./6.jpg" className="transition-transform duration-700 group-hover:scale-[1.01]" />

        {/* 1.jpg 作为桌面悬浮小部件，使用基于外层的百分比宽度 */}
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

// --- 子组件: 移动端展示 (2.jpg 手机 & 2-2.jpg 平板) ---
const AndroidShowcase = () => (
  <section id="mobile" className="py-24 sm:py-40 bg-white overflow-hidden text-center">
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div className="flex flex-col lg:flex-row items-center gap-12 lg:gap-16 text-left">
        {/* 左侧文字区 - 严格限制宽度 */}
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
              { t: "实时同步", d: "跨端操作毫秒级反馈，无缝流转。" },
              { t: "深色模式", d: "完美适配系统深色/浅色模式切换。" }
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

        {/* 右侧展示区 - 基于百分比布局，绝对防止越界 */}
        <div className="lg:w-7/12 w-full flex items-center justify-center relative mt-16 lg:mt-0">

          {/* 手机 (占比父容器宽度约 35%) */}
          <div className="relative z-20 w-[40%] sm:w-[35%] max-w-[260px] transform -rotate-2 hover:rotate-0 transition-all duration-500">
             <MobileFrame src="./2.jpg" />
             <div className="absolute -bottom-6 left-1/2 -translate-x-1/2 bg-white px-3 py-1.5 sm:px-5 sm:py-2.5 rounded-full shadow-xl border border-slate-100 flex items-center gap-1.5 sm:gap-2">
                <div className="w-2 h-2 rounded-full bg-green-500 animate-pulse"></div>
                <span className="text-[10px] sm:text-xs font-black text-slate-700 uppercase tracking-tighter whitespace-nowrap">Phone</span>
             </div>
          </div>

          {/* 平板 (占比父容器宽度约 65%，左侧拉回一部分形成错落堆叠) */}
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

// --- 子组件: 屏幕时间看板 (3,4 手机 & 5 平板) ---
const ScreenTimeShowcase = () => (
  <section id="screentime" className="py-24 sm:py-40 bg-slate-50 overflow-hidden">
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
      <div className="mb-20 sm:mb-32">
        <div className="inline-flex items-center gap-2 px-3 py-1 bg-emerald-50 text-emerald-700 rounded-lg text-xs font-bold uppercase mb-6">
            <PieChart className="w-4 h-4" /> Insight Analytics
        </div>
        <h2 className="text-4xl sm:text-6xl lg:text-7xl font-black text-slate-900 mb-6 sm:mb-8 tracking-tighter">全方位屏幕时间分析</h2>
        <p className="text-slate-500 text-lg sm:text-xl max-w-3xl mx-auto leading-relaxed font-medium px-4">
          整合手机、平板、电脑三端时长数据。不再猜测你的时间去哪了，让数据说话，在任何设备上都能精准掌控每一分钟的产出。
        </p>
      </div>

      {/* 看板多设备布局 - 百分比响应式宽度 */}
      <div className="relative flex flex-col lg:flex-row items-center justify-center w-full max-w-6xl mx-auto">
        <div className="absolute inset-0 bg-indigo-500/5 blur-[200px] rounded-full pointer-events-none"></div>

        {/* 手机群组 */}
        <div className="flex justify-center gap-4 sm:gap-8 z-20 w-full lg:w-5/12 mb-16 lg:mb-0">
          <div className="w-[42%] sm:w-[35%] lg:w-[45%] max-w-[220px] transform translate-y-6 md:translate-y-12 group">
            <MobileFrame src="./3.jpg" className="group-hover:scale-[1.03] transition duration-500" />
            <p className="text-center mt-6 text-[10px] md:text-xs font-black text-slate-400 uppercase tracking-[0.2em] whitespace-nowrap">Usage Details</p>
          </div>
          <div className="w-[42%] sm:w-[35%] lg:w-[45%] max-w-[220px] transform -translate-y-6 md:-translate-y-12 group">
            <MobileFrame src="./4.jpg" className="group-hover:scale-[1.03] transition duration-500" />
            <p className="text-center mt-6 text-[10px] md:text-xs font-black text-slate-400 uppercase tracking-[0.2em] whitespace-nowrap">Time Summary</p>
          </div>
        </div>

        {/* 平板 */}
        <div className="z-10 w-[90%] sm:w-[75%] lg:w-7/12 max-w-[650px] group relative lg:-ml-8">
          <div className="bg-white p-2 sm:p-4 rounded-[1.5rem] sm:rounded-[3rem] shadow-[0_40px_100px_-20px_rgba(0,0,0,0.15)] border border-slate-200 transform group-hover:scale-[1.02] transition-all duration-700">
            <TabletFrame src="./5.jpg" />
          </div>
          <div className="absolute -bottom-6 md:-bottom-10 left-1/2 -translate-x-1/2 flex items-center gap-4 md:gap-8 px-5 md:px-8 py-3 md:py-4 bg-slate-900 rounded-[1.5rem] md:rounded-[2rem] shadow-2xl border border-white/5 whitespace-nowrap">
             <div className="flex flex-col items-center">
                <span className="text-emerald-400 font-black text-sm md:text-lg leading-none">LIVE SYNC</span>
                <span className="text-slate-500 text-[8px] md:text-[10px] font-black mt-1 uppercase tracking-widest">Cloudflare D1</span>
             </div>
             <div className="w-px h-6 md:h-8 bg-slate-800"></div>
             <div className="flex items-center gap-2 md:gap-3">
                <Activity className="w-4 md:w-5 h-4 md:h-5 text-emerald-500" />
                <span className="text-white font-black text-xs md:text-sm tracking-tight italic">Global Dashboard</span>
             </div>
          </div>
        </div>
      </div>
    </div>
  </section>
);

// --- 子组件: 数据看板板块 ---
const AnalyticsPreview = () => (
  <section id="analytics" className="py-24 bg-white text-center">
    <div className="max-w-6xl mx-auto px-4">
      <h2 className="text-4xl font-black mb-10 text-slate-900 tracking-tight">数据聚合，一眼万年</h2>
      <div className="bg-slate-900 p-10 sm:p-20 rounded-[4rem] text-left relative overflow-hidden group shadow-2xl">
         <div className="absolute top-0 right-0 w-96 h-96 bg-indigo-600/10 blur-[120px]"></div>
         <div className="flex flex-col md:flex-row gap-16 items-center">
            <div className="flex-1">
               <div className="flex items-center gap-4 mb-8">
                  <div className="w-12 h-12 bg-indigo-600 rounded-2xl flex items-center justify-center shadow-lg shadow-indigo-500/30">
                     <Database className="text-white w-6 h-6" />
                  </div>
                  <span className="text-white font-black text-2xl tracking-tight">云端字典自动映射</span>
               </div>
               <p className="text-slate-400 leading-relaxed mb-10 text-lg">
                 后端 D1 数据库自动处理全平台应用名映射。无论包名如何差异，在看板中都将合并为最直观的分类，为您还原最真实的时间流向。
               </p>
               <div className="flex flex-wrap gap-3">
                  {['影音娱乐', '学习办公', '系统应用', '通讯社交', '游戏人生'].map(tag => (
                    <span key={tag} className="px-5 py-2 bg-white/5 text-slate-300 text-sm font-bold rounded-full border border-white/5 hover:bg-white/10 transition cursor-default">
                      {tag}
                    </span>
                  ))}
               </div>
            </div>
            <div className="flex-1 grid grid-cols-3 gap-3 w-full opacity-40 group-hover:opacity-100 transition-all duration-700 transform group-hover:rotate-1">
               {[1,2,3,4,5,6,7,8,9].map(i => (
                 <div key={i} className="aspect-square bg-white/5 rounded-2xl border border-white/5 flex flex-col items-center justify-center p-4 hover:border-indigo-500/50 transition">
                   <div className="w-10 h-10 bg-indigo-500/20 rounded-full mb-3 blur-[2px]"></div>
                   <div className="w-12 h-2 bg-white/10 rounded-full mb-1"></div>
                   <div className="w-8 h-1 bg-white/5 rounded-full"></div>
                 </div>
               ))}
            </div>
         </div>
      </div>
    </div>
  </section>
);

// --- 子组件: 下载部分 ---
const DownloadSection = ({ androidInfo, windowsInfo }: { androidInfo: AppInfo, windowsInfo: AppInfo }) => (
  <section id="download" className="py-24 sm:py-48 bg-slate-50 text-center relative overflow-hidden">
    <div className="absolute top-0 left-0 w-full h-px bg-gradient-to-r from-transparent via-slate-200 to-transparent"></div>
    <div className="max-w-6xl mx-auto px-4">
      <h2 className="text-4xl sm:text-7xl font-black mb-8 text-slate-900 tracking-tighter">准备好提升效率了吗？</h2>
      <p className="text-slate-500 mb-20 text-xl font-medium">立刻选择您的设备平台，开启跨设备协同新纪元。</p>

      <div className="grid md:grid-cols-2 gap-10 text-left items-stretch">
        <div className="p-10 sm:p-14 bg-white rounded-[4rem] border border-slate-200 shadow-sm hover:shadow-2xl hover:border-blue-500 transition-all group flex flex-col relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-blue-500/5 rounded-full blur-3xl group-hover:bg-blue-500/10 transition"></div>
          <div className="w-16 h-16 bg-blue-50 text-blue-600 rounded-[1.5rem] flex items-center justify-center mb-8 group-hover:scale-110 group-hover:rotate-3 transition duration-500 shadow-sm"><Monitor className="w-8 h-8" /></div>
          <h3 className="text-3xl font-black mb-4 text-slate-900 tracking-tight">Windows Lite</h3>
          <p className="text-slate-500 text-lg mb-10 flex-1 leading-relaxed">
             v{windowsInfo.version || '1.0.0'} <br/>
             {windowsInfo.desc || '原生 C++ 高性能架构，内存占用 < 30MB，零感常驻桌面，给您最纯净的待办体验。'}
          </p>
          <div className="space-y-4">
             <a href={windowsInfo.url || "#"} className="flex items-center justify-center gap-3 bg-blue-600 text-white w-full py-5 rounded-2xl font-black text-lg hover:bg-blue-700 transition shadow-xl shadow-blue-500/30">获取下载 <ChevronRight className="w-6 h-6" /></a>
             <div className="flex items-center justify-between px-6 py-3 bg-blue-50 rounded-2xl text-xs text-blue-700 font-black border border-blue-100">
                <span>依赖 Tai 核心服务</span>
                <a href="https://github.com/Planshit/Tai/releases/download/1.5.0.6/Tai1.5.0.6.zip" target="_blank" rel="noreferrer" className="underline hover:text-blue-900">立即前往</a>
             </div>
          </div>
        </div>

        <div className="p-10 sm:p-14 bg-white rounded-[4rem] border border-slate-200 shadow-sm hover:shadow-2xl hover:border-indigo-500 transition-all group flex flex-col relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-indigo-500/5 rounded-full blur-3xl group-hover:bg-indigo-500/10 transition"></div>
          <div className="w-16 h-16 bg-indigo-50 text-indigo-600 rounded-[1.5rem] flex items-center justify-center mb-8 group-hover:scale-110 group-hover:-rotate-3 transition duration-500 shadow-sm"><Smartphone className="w-8 h-8" /></div>
          <h3 className="text-3xl font-black mb-4 text-slate-900 tracking-tight">Android Pro</h3>
          <p className="text-slate-500 text-lg mb-10 flex-1 leading-relaxed">
             v{androidInfo.version || '1.0.0'} <br/>
             {androidInfo.desc || '沉浸式 Flutter 交互，Material 3 视觉盛宴，深度全平台屏幕时间分析。'}
          </p>
          <a href={androidInfo.url || "#"} className="flex items-center justify-center gap-3 bg-indigo-600 text-white w-full py-5 rounded-2xl font-black text-lg hover:bg-indigo-700 transition shadow-xl shadow-indigo-500/30">立即安装 <ChevronRight className="w-6 h-6" /></a>
        </div>
      </div>
    </div>
  </section>
);

// --- 主组件: App ---
const App = () => {
  const [androidInfo, setAndroidInfo] = useState<AppInfo>({ version: '', url: '', desc: '' });
  const [windowsInfo, setWindowsInfo] = useState<AppInfo>({ version: '', url: '', desc: '' });

  useEffect(() => {
    const fetchManifests = async () => {
      try {
        const [aRes, wRes] = await Promise.all([
          fetch('https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json'),
          fetch('https://raw.githubusercontent.com/Junpgle/CountDownTodoLite/refs/heads/master/update_manifest.json')
        ]);
        const [aData, wData] = await Promise.all([aRes.json(), wRes.json()]);
        setAndroidInfo({ version: aData.version_name, url: aData.update_info.full_package_url, desc: aData.update_info.description });
        setWindowsInfo({ version: wData.version_name, url: wData.update_info.full_package_url, desc: wData.update_info.description });
      } catch (e) { console.error("Manifest error", e); }
    };
    fetchManifests();
  }, []);

  return (
    <div className="bg-white min-h-screen font-sans selection:bg-indigo-600 selection:text-white antialiased">
      <Navbar />
      <Hero />
      <Features />
      <WindowsShowcase />
      <AndroidShowcase />
      <ScreenTimeShowcase />
      <AnalyticsPreview />
      <DownloadSection androidInfo={androidInfo} windowsInfo={windowsInfo} />

      <footer className="bg-white py-20 border-t border-slate-100 text-center">
        <div className="flex flex-col items-center">
          <div className="flex items-center justify-center gap-2 mb-8">
            <div className="bg-indigo-600 p-2 rounded-lg shadow-lg shadow-indigo-500/20">
               <Layers className="text-white w-5 h-5" />
            </div>
            <span className="font-black text-2xl text-slate-900 tracking-tighter">CountDownTodo</span>
          </div>
          <div className="flex gap-10 mb-10">
             <a href="#features" className="text-slate-400 hover:text-indigo-600 font-bold transition">核心特性</a>
             <a href="#download" className="text-slate-400 hover:text-indigo-600 font-bold transition">获取下载</a>
             <a href="https://github.com/Junpgle" target="_blank" className="text-slate-400 hover:text-indigo-600 font-bold transition">开发者</a>
          </div>
          <p className="text-slate-300 text-xs font-black uppercase tracking-[0.3em] mb-2">Designed for Productivity</p>
          <p className="text-slate-400 text-xs font-bold">© 2026 JUNPGLE. ALL RIGHTS RESERVED.</p>
        </div>
      </footer>

      <style dangerouslySetInnerHTML={{ __html: `
        @keyframes bounce-subtle { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-15px); } }
        .animate-bounce-subtle { animation: bounce-subtle 4s ease-in-out infinite; }
        html { scroll-behavior: smooth; }
        body { text-rendering: optimizeLegibility; -webkit-font-smoothing: antialiased; }
      `}} />
    </div>
  );
};

export default App;