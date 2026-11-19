import { useState, useEffect } from 'react';
import {
  Download,
  Globe,
  Github,
  Sparkles,
  Watch,
  Smartphone,
  Monitor,
  Command,
} from 'lucide-react';

const particleStyles = Array.from({ length: 8 }, (_, index) => ({
  width: (10 + (index * 17) % 25) + 'px',
  height: (10 + (index * 11) % 25) + 'px',
  left: ((index * 37 + 11) % 100) + '%',
  top: ((index * 29 + 7) % 100) + '%',
  animationDelay: ((index * 3) % 5) + 's',
  animationDuration: (8 + (index * 7) % 12) + 's',
}));

export const Hero = ({ version, date }: { version?: string; date?: string }) => {
  const [activeMessageIndex, setActiveMessageIndex] = useState(0);

  const messages = [
    `最新版本: v${version || '7.24.8'}`,
    `更新于: ${date || '2026-11-17'}`,
  ];

  useEffect(() => {
    const timer = setInterval(() => {
      setActiveMessageIndex((prev) => (prev + 1) % messages.length);
    }, 4000);
    return () => clearInterval(timer);
  }, [messages.length]);

  return (
    <section className="relative min-h-[95vh] flex items-center pt-28 pb-20 overflow-hidden liquid-ambient-bg selection:bg-indigo-100">
      {/* Dynamic Background */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div className="absolute top-1/2 left-1/2 w-[140%] h-[140%] bg-[radial-gradient(circle_at_center,_var(--tw-gradient-from)_0%,_transparent_60%)] from-indigo-100/50 animate-spotlight -z-10"></div>
        <div className="absolute top-[-10%] left-[-10%] w-[45%] h-[45%] bg-gradient-to-br from-indigo-300/35 to-sky-200/35 rounded-full blur-[120px] animate-blob"></div>
        <div className="absolute top-[20%] right-[-10%] w-[40%] h-[40%] bg-gradient-to-br from-purple-300/35 to-pink-200/35 rounded-full blur-[120px] animate-blob animation-delay-2000"></div>
        <div className="absolute bottom-[-10%] left-[20%] w-[35%] h-[35%] bg-gradient-to-br from-emerald-200/35 to-teal-200/35 rounded-full blur-[120px] animate-blob animation-delay-4000"></div>
        {particleStyles.map((style, i) => (
          <div
            key={i}
            className="absolute bg-indigo-500/10 rounded-full blur-[2px] animate-float"
            style={style}
          />
        ))}
        <div className="absolute inset-0 opacity-[0.035]" style={{ backgroundImage: 'radial-gradient(#000 1.2px, transparent 1.2px)', backgroundSize: '48px 48px' }}></div>
      </div>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10 w-full">
        <div className="flex flex-col lg:flex-row items-center gap-16 lg:gap-20">
          {/* Content Column */}
          <div className="flex-[1.1] text-center lg:text-left">
            <div className="inline-flex items-center gap-3 px-5 py-2.5 rounded-full liquid-glass-dark liquid-glass-iridescent text-white text-xs sm:text-sm font-bold mb-10 animate-fade-in-up">
              <Sparkles className="w-4 h-4 text-amber-300" />
              <span>CountDownTodo 7.24 全新进化</span>
              <div className="w-px h-4 bg-white/20 mx-1"></div>
              <div className="relative h-5 overflow-hidden min-w-[140px] text-white/75">
                {messages.map((msg, i) => (
                  <div
                    key={i}
                    className={`absolute inset-0 transition-all duration-700 flex items-center whitespace-nowrap ${
                      i === activeMessageIndex ? 'translate-y-0 opacity-100' : 'translate-y-full opacity-0'
                    }`}
                  >
                    {msg}
                  </div>
                ))}
              </div>
            </div>

            <h1 className="text-6xl sm:text-7xl xl:text-8xl font-black tracking-tight mb-8 leading-[1.02] text-slate-900">
              掌控时间<br />
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-indigo-600 via-violet-600 via-purple-600 via-pink-600 to-rose-600 animate-text-gradient">
                从容生活
              </span>
            </h1>

            <p className="text-lg sm:text-2xl text-slate-600/90 max-w-xl mx-auto lg:mx-0 mb-12 leading-relaxed font-medium">
              横跨手机、平板、桌面与小米手环。集课表规划、AI 助手、个人记账与习惯养成于一体，让每一天清晰有序。
            </p>

            <div className="flex flex-col sm:flex-row flex-wrap items-center justify-center lg:justify-start gap-4 sm:gap-5 mb-14">
              <a href="#download" className="group relative flex items-center justify-center gap-3 bg-indigo-600 text-white px-9 py-5 rounded-[2rem] text-lg font-bold hover:bg-indigo-700 transition-all shadow-[0_20px_50px_rgba(79,70,229,0.3)] hover:-translate-y-1.5 w-full sm:w-auto overflow-hidden">
                <div className="absolute inset-0 bg-gradient-to-r from-transparent via-white/25 to-transparent -translate-x-full group-hover:translate-x-full transition-transform duration-1000"></div>
                <Download className="w-6 h-6" /> 立即下载
              </a>
              <a href="https://cdt.junpgle.me/" target="_blank" rel="noreferrer" className="group flex items-center justify-center gap-3 liquid-glass text-slate-900 px-8 py-5 rounded-[2rem] text-lg font-bold hover:bg-white/90 transition-all hover:-translate-y-1.5 w-full sm:w-auto">
                <Globe className="w-6 h-6 text-indigo-600 group-hover:rotate-12 transition-transform" /> 网页版 Beta
              </a>
              <a href="https://github.com/Junpgle/CountdownTodo" target="_blank" rel="noreferrer" className="group flex items-center justify-center gap-2.5 liquid-glass-dark text-white px-7 py-5 rounded-[2rem] text-lg font-bold hover:bg-slate-900 transition-all hover:-translate-y-1.5 w-full sm:w-auto">
                <Github className="w-5 h-5 group-hover:scale-110 transition-transform" /> GitHub
              </a>
            </div>

            {/* Platform Badges Grid */}
            <div className="grid grid-cols-3 sm:grid-cols-6 gap-4 sm:gap-6 opacity-55 hover:opacity-100 transition-all duration-500">
              {[
                { Icon: Monitor, label: 'Windows' },
                { Icon: Command, label: 'macOS x64/arm' },
                { Icon: Smartphone, label: 'Android / Pad' },
                { Icon: Watch, label: 'Mi Band' },
                { Icon: Globe, label: 'Web PWA', href: 'https://cdt.junpgle.me/' },
                { Icon: Github, label: 'GitHub', href: 'https://github.com/Junpgle/CountdownTodo' },
              ].map(({ Icon, label, href }, i) =>
                href ? (
                  <a
                    key={i}
                    href={href}
                    target="_blank"
                    rel="noreferrer"
                    className="flex flex-col items-center lg:items-start gap-2 group"
                  >
                    <div className="p-2 rounded-lg bg-slate-100 group-hover:bg-indigo-50 transition-colors">
                      <Icon className="w-5 h-5 group-hover:text-indigo-600" />
                    </div>
                    <span className="text-[10px] font-black uppercase tracking-[0.12em] group-hover:text-indigo-600 transition-colors">{label}</span>
                  </a>
                ) : (
                  <div key={i} className="flex flex-col items-center lg:items-start gap-2 group cursor-default">
                    <div className="p-2 rounded-lg bg-slate-100 group-hover:bg-indigo-50 transition-colors">
                      <Icon className="w-5 h-5 group-hover:text-indigo-600" />
                    </div>
                    <span className="text-[10px] font-black uppercase tracking-[0.12em]">{label}</span>
                  </div>
                ),
              )}
            </div>
          </div>

          {/* Visual Column: Real Multi-Device Screenshots */}
          <div className="flex-1 relative w-full">
            <div className="relative z-10 group">
              {/* Desktop / Tablet Main Screen */}
              <div className="rounded-[2rem] sm:rounded-[2.5rem] liquid-glass liquid-glass-iridescent p-2.5 sm:p-3.5 overflow-hidden transform hover:scale-[1.01] transition-transform duration-700">
                <img
                  src="./tablet_home_v2.jpg"
                  alt="CountDownTodo 桌面与平板双栏主界面"
                  fetchPriority="high"
                  className="w-full h-auto rounded-[1.5rem] sm:rounded-[2rem] object-cover"
                />
              </div>

              {/* Overlapping Mobile Screenshot */}
              <div className="hidden sm:block absolute -bottom-8 -left-6 w-[32%] max-w-[185px] rounded-[2rem] liquid-glass-dark liquid-glass-iridescent p-1.5 transform -rotate-3 hover:rotate-0 hover:scale-105 transition-all duration-500 z-20">
                <img
                  src="./mobile_home_v2.jpg"
                  alt="CountDownTodo 手机端主界面"
                  fetchPriority="high"
                  className="w-full h-auto rounded-[1.6rem] object-cover"
                />
              </div>

              {/* Floating macOS Dynamic Island Badge */}
              <div className="hidden sm:flex absolute -top-6 -right-4 liquid-glass-dark text-white px-5 py-3.5 rounded-2xl items-center gap-3 z-20 animate-bounce-subtle">
                <div className="w-9 h-9 rounded-xl bg-gradient-to-tr from-indigo-500 to-sky-400 flex items-center justify-center shrink-0">
                  <Sparkles className="w-4 h-4 text-white" />
                </div>
                <div className="text-left">
                  <div className="text-[10px] font-bold text-sky-300 uppercase tracking-wider">Liquid Glass UI</div>
                  <div className="text-xs font-black">多端同步 · 灵动岛常驻</div>
                </div>
              </div>
            </div>

            <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[130%] h-[130%] bg-[radial-gradient(circle,_var(--tw-gradient-from)_0%,_transparent_70%)] from-indigo-500/10 blur-[120px] rounded-full -z-10 animate-pulse"></div>
          </div>
        </div>
      </div>
    </section>
  );
};
