import { useState, useEffect, useRef } from 'react';
import {
  Layers, Monitor, Smartphone, CloudLightning, Download, Github,
  CheckCircle2, Menu, X, ChevronRight, Database, Cpu, PieChart,
  Tablet as TabletIcon, BellRing, CalendarDays, MonitorSmartphone,
  Globe, LayoutDashboard, Sparkles, ArrowRight
} from 'lucide-react';
import { MobileFrame, TabletFrame, MonitorFrame } from '../components/Frames';
import type { AppInfo } from '../types';

/* =========================
   子组件：导航栏
========================= */
const Navbar = ({ onOpenWeb }: { onOpenWeb: () => void }) => {
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
    { name: '网页版', href: '#web' },
    { name: '获取软件', href: '#download' },
  ];

  return (
    <nav className={`fixed w-full z-50 transition-all duration-500 ${isScrolled ? 'bg-white/90 backdrop-blur-xl border-b border-slate-200 shadow-sm' : 'bg-transparent'}`}>
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center h-16 sm:h-20">
          <div className="flex items-center gap-2 group cursor-pointer">
            <div className="bg-indigo-600 p-1.5 sm:p-2 rounded-lg group-hover:rotate-12 transition-transform duration-300 shadow-lg shadow-indigo-500/30">
              <Layers className="text-white w-5 h-5 sm:w-6 sm:h-6" />
            </div>
            <span className="font-bold text-xl sm:text-2xl tracking-tight text-slate-900">CountDownTodo</span>
          </div>

          <div className="hidden lg:flex space-x-6 xl:space-x-8 items-center">
            {navLinks.map((link) => (
              <a key={link.name} href={link.href} className="text-slate-600 hover:text-indigo-600 font-semibold transition-colors duration-300 text-sm xl:text-base">{link.name}</a>
            ))}
            <div className="h-6 w-px bg-slate-200 mx-2"></div>
            <button onClick={onOpenWeb} className="text-indigo-600 hover:text-indigo-800 font-bold transition-colors duration-300 text-sm xl:text-base">网页版入口</button>
            <a href="#download" className="bg-indigo-600 hover:bg-indigo-700 text-white px-5 lg:px-6 py-2 sm:py-2.5 rounded-full font-bold transition-all shadow-lg shadow-indigo-500/30 hover:-translate-y-0.5 active:scale-95">免费获取</a>
          </div>

          <div className="lg:hidden flex items-center gap-4">
            <button onClick={onOpenWeb} className="text-indigo-600 font-bold text-sm">网页版</button>
            <button onClick={() => setMobileMenuOpen(!mobileMenuOpen)} className="p-2 text-slate-600 hover:bg-slate-100 rounded-lg transition">
              {mobileMenuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
            </button>
          </div>
        </div>
      </div>
      {mobileMenuOpen && (
        <div className="lg:hidden bg-white/95 backdrop-blur-2xl border-b border-slate-200 shadow-xl absolute w-full transition-all">
          <div className="px-4 pt-2 pb-6 space-y-2">
            {navLinks.map((link) => (
              <a key={link.name} href={link.href} onClick={() => setMobileMenuOpen(false)} className="block px-4 py-3 text-base font-bold text-slate-700 hover:bg-indigo-50 hover:text-indigo-600 rounded-xl transition">{link.name}</a>
            ))}
            <div className="pt-4 pb-2 px-2 flex flex-col gap-3">
              <button onClick={() => { onOpenWeb(); setMobileMenuOpen(false); }} className="w-full text-center bg-indigo-50 text-indigo-700 border border-indigo-100 py-3.5 rounded-xl font-bold">在线体验网页版</button>
              <a href="#download" onClick={() => setMobileMenuOpen(false)} className="block w-full text-center bg-indigo-600 text-white py-3.5 rounded-xl font-bold shadow-lg shadow-indigo-500/20">立即下载</a>
            </div>
          </div>
        </div>
      )}
    </nav>
  );
};

/* =========================
   子组件：Hero
========================= */
const Hero = ({ onOpenWeb }: { onOpenWeb: () => void }) => (
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
        <button onClick={onOpenWeb} className="flex items-center justify-center gap-3 bg-white text-indigo-600 border border-indigo-100 px-8 py-4 sm:px-10 sm:py-4 rounded-2xl text-base sm:text-lg font-bold hover:bg-indigo-50 transition-all hover:-translate-y-1 shadow-md w-full sm:w-auto">
          <Globe className="w-5 h-5" /> 进入网页站
        </button>
        <a href="https://github.com/Junpgle/CountdownTodo" target="_blank" rel="noreferrer" className="flex items-center justify-center gap-3 bg-white text-slate-700 border border-slate-200 px-8 py-4 sm:px-10 sm:py-4 rounded-2xl text-base sm:text-lg font-bold hover:bg-slate-50 transition-all hover:-translate-y-1 shadow-sm w-full sm:w-auto">
          <Github className="w-5 h-5" /> 开源仓库
        </a>
      </div>
    </div>
    <div className="absolute top-0 left-1/2 -translate-x-1/2 w-full h-full -z-10 pointer-events-none opacity-[0.03]" style={{ backgroundImage: 'radial-gradient(#000 1px, transparent 1px)', backgroundSize: '30px 30px' }}></div>
  </section>
);

/* =========================
   子组件：网页版功能展示
========================= */
const WebShowcase = ({ onOpenWeb }: { onOpenWeb: () => void }) => (
  <section id="web" className="py-24 sm:py-40 bg-slate-900 overflow-hidden relative">
    <div className="absolute inset-0 bg-gradient-to-b from-slate-900 via-indigo-900/20 to-slate-900 pointer-events-none"></div>
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
      <div className="text-center mb-20">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-indigo-500/20 text-indigo-400 rounded-lg text-sm font-bold uppercase tracking-widest mb-6">
          <MonitorSmartphone className="w-5 h-5" /> Cloud Desktop Station
        </div>
        <h2 className="text-4xl sm:text-6xl font-black mb-6 tracking-tight text-white">Web Pro 全球网页工作站</h2>
        <p className="text-slate-400 text-lg sm:text-xl max-w-3xl mx-auto leading-relaxed font-medium">
          无需下载，任何设备打开浏览器即刻进入。专为桌面大屏重构的 Dashboard 布局，深度整合智能课表、待办分栏与数据仪表盘。
        </p>
      </div>

      <div className="grid lg:grid-cols-2 gap-12 lg:gap-20 items-center">
        <div className="space-y-10 order-2 lg:order-1">
          <div className="group bg-slate-800/50 p-3 rounded-[2.5rem] shadow-2xl border border-white/5 transform hover:-translate-y-2 transition-all duration-700">
            <div className="flex items-center gap-2 px-6 py-4 border-b border-white/5 bg-white/5 rounded-t-[2.2rem]">
               <div className="flex gap-1.5">
                  <div className="w-3 h-3 rounded-full bg-red-500/50"></div>
                  <div className="w-3 h-3 rounded-full bg-amber-500/50"></div>
                  <div className="w-3 h-3 rounded-full bg-green-500/50"></div>
               </div>
               <span className="text-xs font-mono text-slate-500 ml-4 font-bold tracking-tight">app.countdowntodo.com</span>
            </div>
            <img src="./11.jpg" alt="网页版主界面" className="w-full rounded-b-[2rem] shadow-inner" />
            <div className="p-8">
              <h3 className="text-2xl font-bold text-white mb-3 flex items-center gap-2">
                <LayoutDashboard className="w-6 h-6 text-indigo-400" />
                全能工作仪表盘
              </h3>
              <p className="text-slate-400 leading-relaxed">左侧 50% 嵌入自适应周视图课表，右侧 1/5 聚焦倒计时，4/5 管理待办清单。完美利用屏幕宽度，效率一眼全收。</p>
            </div>
          </div>
          <button onClick={onOpenWeb} className="w-full flex items-center justify-center gap-3 bg-indigo-600 text-white px-10 py-5 rounded-2xl font-black text-xl hover:bg-indigo-700 transition shadow-2xl shadow-indigo-500/40 hover:-translate-y-1 active:scale-95">
            立即开启网页站 <ChevronRight className="w-6 h-6" />
          </button>
        </div>

        <div className="order-1 lg:order-2 lg:pt-32">
          <div className="group bg-slate-800/50 p-3 rounded-[2.5rem] shadow-2xl border border-white/5 transform hover:-translate-y-2 transition-all duration-700">
            <div className="flex items-center gap-2 px-6 py-4 border-b border-white/5 bg-white/5 rounded-t-[2.2rem]">
               <span className="text-xs font-mono text-slate-500 font-bold tracking-widest uppercase">Insight analytics</span>
            </div>
            <img src="./12.jpg" alt="网页版屏幕使用时间" className="w-full rounded-b-[2rem] shadow-inner" />
            <div className="p-8">
              <h3 className="text-2xl font-bold text-white mb-3 flex items-center gap-2">
                <PieChart className="w-6 h-6 text-emerald-400" />
                深度时耗看板
              </h3>
              <p className="text-slate-400 leading-relaxed">全屏精美统计图表，多维度分析手机、平板与电脑的使用时长分布，还原最真实的时间流向，让掌控力跃然屏上。</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>
);

/* =========================
   子组件：功能特性列表
========================= */
const Features = () => {
  const features = [
    { title: "桌面端 (Win32)", desc: "C++17 原生开发。Layered Window 透明渲染，极低内存占用 (<30MB)，常驻桌面不打扰。", icon: <Monitor className="w-6 h-6" />, color: "bg-blue-50 text-blue-600" },
    { title: "移动端 (Flutter)", desc: "Material 3 规范与沉浸式交互。三级应用分类分析，动态壁纸切换，Android 16 实时通知完美适配。", icon: <Smartphone className="w-6 h-6" />, color: "bg-purple-50 text-purple-600" },
    { title: "云端同步 (D1)", desc: "创新引入 Batch 批量同步与 Delta 增量合并策略。跨设备毫秒级分发，确保极端网络下的数据一致性。", icon: <CloudLightning className="w-6 h-6" />, color: "bg-amber-50 text-amber-600" }
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

/* =========================
   子组件：Windows 展示
========================= */
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

/* =========================
   子组件：Android 展示
========================= */
const AndroidShowcase = () => (
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

/* =========================
   子组件：智能课表展示
========================= */
const TimetableShowcase = () => {
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
                <img src="./8.jpg" alt="PC 端日历课表" className="w-full rounded-xl sm:rounded-2xl border border-slate-100" onError={(e) => { e.currentTarget.src = 'https://images.unsplash.com/photo-1506784951209-6854d59ab2a2?auto=format&fit=crop&q=80&w=1200'; }} />
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

/* =========================
   子组件：灵动同步展示
========================= */
const LiveUpdatesShowcase = () => {
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

/* =========================
   子组件：数据分析预览
========================= */
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

/* =========================
   子组件：获取软件 (三列矩阵版)
========================= */
const DownloadSection = ({ androidInfo, windowsInfo, webInfo, onOpenWeb }: { androidInfo: AppInfo, windowsInfo: AppInfo, webInfo: AppInfo, onOpenWeb: () => void }) => (
  <section id="download" className="py-24 sm:py-48 bg-slate-50 text-center relative overflow-hidden">
    <div className="absolute top-0 left-0 w-full h-px bg-gradient-to-r from-transparent via-slate-200 to-transparent"></div>
    <div className="max-w-7xl mx-auto px-4">
      <h2 className="text-4xl sm:text-7xl font-black mb-8 text-slate-900 tracking-tighter">准备好开启高效生活了吗？</h2>
      <p className="text-slate-500 mb-20 text-xl font-medium">全平台支持，数据实时流转，选择适合您的工作方式。</p>

      <div className="grid lg:grid-cols-3 gap-8 text-left items-stretch">
        {/* Windows */}
        <div className="p-8 sm:p-10 bg-white rounded-[3rem] border border-slate-200 shadow-sm hover:shadow-2xl hover:border-blue-500 transition-all group flex flex-col relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-blue-500/5 rounded-full blur-3xl group-hover:bg-blue-500/10 transition"></div>
          <div className="w-14 h-14 bg-blue-50 text-blue-600 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 group-hover:rotate-3 transition duration-500 shadow-sm"><Monitor className="w-7 h-7" /></div>
          <h3 className="text-2xl font-black mb-3 text-slate-900 tracking-tight">Windows Lite</h3>
          <p className="text-slate-500 text-base mb-8 flex-1 leading-relaxed whitespace-pre-line">
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

        {/* Android */}
        <div className="p-8 sm:p-10 bg-white rounded-[3rem] border border-slate-200 shadow-sm hover:shadow-2xl hover:border-purple-500 transition-all group flex flex-col relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-purple-500/5 rounded-full blur-3xl group-hover:bg-purple-500/10 transition"></div>
          <div className="w-14 h-14 bg-purple-50 text-purple-600 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 group-hover:-rotate-3 transition duration-500 shadow-sm"><Smartphone className="w-7 h-7" /></div>
          <h3 className="text-2xl font-black mb-3 text-slate-900 tracking-tight">Android Pro</h3>
          <p className="text-slate-500 text-base mb-8 flex-1 leading-relaxed whitespace-pre-line">
             v{androidInfo.version || '1.0.0'} <br/>
             {androidInfo.desc || '沉浸式 Flutter 交互，Material 3 视觉盛宴，深度屏幕时间分析。'}
          </p>
          <a href={androidInfo.url || "#"} className="flex items-center justify-center gap-3 bg-purple-600 text-white w-full py-4 rounded-xl font-black text-lg hover:bg-purple-700 transition shadow-xl shadow-purple-500/30">获取安装包 <ChevronRight className="w-6 h-6" /></a>
        </div>

        {/* Web (Entry Updated with Fetch Data) */}
        <div className="p-8 sm:p-10 bg-white rounded-[3rem] border border-slate-200 shadow-sm hover:shadow-2xl hover:border-indigo-500 transition-all group flex flex-col relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-indigo-500/5 rounded-full blur-3xl group-hover:bg-indigo-500/10 transition"></div>
          <div className="w-14 h-14 bg-indigo-50 text-indigo-600 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 group-hover:rotate-6 transition duration-500 shadow-sm"><Globe className="w-7 h-7" /></div>
          <h3 className="text-2xl font-black mb-3 text-slate-900 tracking-tight">Web Station</h3>
          <p className="text-slate-500 text-base mb-8 flex-1 leading-relaxed whitespace-pre-line">
             v{webInfo.version || '1.0.0'} <br/>
             {webInfo.desc || '云端仪表盘，免安装即开即用。深度同步课表与待办，您的跨平台数据中枢。'}
          </p>
          <button onClick={onOpenWeb} className="flex items-center justify-center gap-3 bg-indigo-600 text-white w-full py-4 rounded-xl font-black text-lg hover:bg-indigo-700 transition shadow-xl shadow-indigo-500/30">立即开启网页版 <ArrowRight className="w-6 h-6" /></button>
        </div>
      </div>
    </div>
  </section>
);

/* =========================
   主页面容器：LandingPage
========================= */
export const LandingPage = ({ onOpenWeb }: { onOpenWeb: () => void }) => {
  const [androidInfo, setAndroidInfo] = useState<AppInfo>({ version: '', url: '', desc: '' });
  const [windowsInfo, setWindowsInfo] = useState<AppInfo>({ version: '', url: '', desc: '' });
  const [webInfo, setWebInfo] = useState<AppInfo>({ version: '', url: '', desc: '' });

  useEffect(() => {
    const fetchManifests = async () => {
      try {
        const [aRes, wRes, webRes] = await Promise.all([
          fetch('https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json'),
          fetch('https://raw.githubusercontent.com/Junpgle/CountDownTodoLite/refs/heads/master/update_manifest.json'),
          fetch('https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/webpage/web/update_manifest.json')
        ]);
        const [aData, wData, webData] = await Promise.all([aRes.json(), wRes.json(), webRes.json()]);

        setAndroidInfo({
          version: aData.version_name,
          url: aData.update_info.full_package_url,
          desc: aData.update_info.description
        });

        setWindowsInfo({
          version: wData.version_name,
          url: wData.update_info.full_package_url,
          desc: wData.update_info.description
        });

        setWebInfo({
          version: webData.version_name,
          url: '', // 网页版不需要下载URL
          desc: webData.update_info.description
        });

      } catch (e) {
        console.error("Manifest JSON 解析拉取错误:", e);
      }
    };
    fetchManifests();
  }, []);

  return (
    <div className="bg-white min-h-screen">
      <Navbar onOpenWeb={onOpenWeb} />
      <Hero onOpenWeb={onOpenWeb} />
      <Features />
      <WindowsShowcase />
      <AndroidShowcase />
      <WebShowcase onOpenWeb={onOpenWeb} />
      <TimetableShowcase />
      <LiveUpdatesShowcase />
      <AnalyticsPreview />
      <DownloadSection androidInfo={androidInfo} windowsInfo={windowsInfo} webInfo={webInfo} onOpenWeb={onOpenWeb} />

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
             <button onClick={onOpenWeb} className="text-slate-400 hover:text-indigo-600 font-bold transition">网页版体验</button>
             <a href="https://github.com/Junpgle" target="_blank" rel="noreferrer" className="text-slate-400 hover:text-indigo-600 font-bold transition">开发者</a>
          </div>
          <p className="text-slate-300 text-xs font-black uppercase tracking-[0.3em] mb-2">Designed for Productivity</p>
          <p className="text-slate-400 text-xs font-bold">© 2026 JUNPGLE. ALL RIGHTS RESERVED.</p>
        </div>
      </footer>
    </div>
  );
};