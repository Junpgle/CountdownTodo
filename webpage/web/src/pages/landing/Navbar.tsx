import { useState, useEffect, useLayoutEffect, useRef } from 'react';
import { Menu, X, BookOpen } from 'lucide-react';
import { GUIDE_LINKS, type LandingTabId } from '../../constants/links';

interface NavbarProps {
  activeTab: LandingTabId;
  onSelectTab: (tab: LandingTabId, anchorId?: string) => void;
}

const NAV_TABS: Array<{ id: LandingTabId; name: string }> = [
  { id: 'overview', name: '总览' },
  { id: 'ai', name: 'AI 助手 2.0' },
  { id: 'planning', name: '规划与协作' },
  { id: 'finance-growth', name: '记账与成长' },
  { id: 'sync-platforms', name: '多端与同步' },
];

export const Navbar = ({ activeTab, onSelectTab }: NavbarProps) => {
  const [isScrolled, setIsScrolled] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const tabButtonRefs = useRef<Partial<Record<LandingTabId, HTMLButtonElement | null>>>({});
  const indicatorRef = useRef<HTMLSpanElement | null>(null);
  const hasInitializedIndicator = useRef(false);

  useEffect(() => {
    const handleScroll = () => setIsScrolled(window.scrollY > 20);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  useLayoutEffect(() => {
    const updateIndicator = (animate: boolean) => {
      const indicator = indicatorRef.current;
      const activeButton = tabButtonRefs.current[activeTab];
      if (!indicator || !activeButton) return;

      if (!animate) {
        indicator.style.transition = 'none';
      } else {
        indicator.style.transition = '';
      }

      indicator.style.width = `${activeButton.offsetWidth}px`;
      indicator.style.transform = `translate3d(${activeButton.offsetLeft}px, 0, 0)`;
      indicator.style.opacity = '1';

      if (!animate) {
        // Force reflow so subsequent switches animate smoothly from initial position
        void indicator.offsetWidth;
        indicator.style.transition = '';
      }
    };

    updateIndicator(hasInitializedIndicator.current);
    hasInitializedIndicator.current = true;

    const handleResize = () => updateIndicator(false);
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, [activeTab]);

  const handleTabClick = (tab: LandingTabId, anchorId?: string) => {
    setMobileMenuOpen(false);
    onSelectTab(tab, anchorId);
  };

  const pillSurface =
    isScrolled || activeTab !== 'overview'
      ? 'liquid-glass-pill liquid-glass-iridescent'
      : 'liquid-glass-pill';

  return (
    <nav className="fixed top-0 left-0 right-0 z-50 pt-3 sm:pt-4 px-3 sm:px-6 pointer-events-none">
      <div className="max-w-7xl mx-auto flex items-center justify-between gap-3">
        {/* 左侧胶囊：品牌 Logo */}
        <button
          type="button"
          onClick={() => handleTabClick('overview')}
          className={`pointer-events-auto flex items-center gap-2.5 px-3.5 sm:px-4 h-12 sm:h-14 rounded-full group cursor-pointer shrink-0 text-left transition-all duration-500 ${pillSurface}`}
        >
          <img
            src="./app_icon.webp"
            alt="CountDownTodo"
            className="w-7 h-7 sm:w-8 sm:h-8 rounded-xl shadow-md shadow-blue-500/20 object-contain group-hover:scale-105 transition-transform duration-300"
          />
          <span className="font-bold text-base sm:text-lg tracking-tight text-slate-900">CountDownTodo</span>
        </button>

        {/* 中间胶囊：核心专题切换（带左右平移动画指示器） */}
        <div
          className={`relative hidden lg:flex items-center gap-1 px-2 h-14 rounded-full pointer-events-auto transition-all duration-500 ${pillSurface}`}
        >
          <span
            ref={indicatorRef}
            aria-hidden="true"
            className="pointer-events-none absolute left-0 top-2 bottom-2 rounded-full bg-indigo-600/12 border border-indigo-200/75 shadow-[inset_0_1px_1px_rgba(255,255,255,0.9),0_2px_8px_rgba(99,102,241,0.14)] opacity-0 motion-safe:transition-[transform,width,opacity] motion-safe:duration-350 motion-safe:ease-[cubic-bezier(0.32,0.72,0,1)]"
          />
          {NAV_TABS.map((tab) => {
            const isActive = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                ref={(el) => {
                  tabButtonRefs.current[tab.id] = el;
                }}
                type="button"
                onClick={() => handleTabClick(tab.id)}
                className={`relative z-10 px-3.5 py-2 rounded-full font-semibold transition-colors duration-300 text-sm whitespace-nowrap cursor-pointer ${
                  isActive
                    ? 'text-indigo-700 font-bold'
                    : 'text-slate-600 hover:text-indigo-600'
                }`}
              >
                {tab.name}
              </button>
            );
          })}
        </div>

        {/* 右侧胶囊：指南、网页版 & 下载 */}
        <div
          className={`hidden lg:flex items-center gap-1.5 pl-3.5 pr-1.5 h-14 rounded-full pointer-events-auto shrink-0 transition-all duration-500 ${pillSurface}`}
        >
          <a
            href={GUIDE_LINKS.docsHub}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-full text-slate-600 hover:text-indigo-600 hover:bg-white/60 font-semibold transition-colors duration-300 text-sm whitespace-nowrap"
          >
            <BookOpen className="w-4 h-4" /> 高阶指南
          </a>
          <a
            href={GUIDE_LINKS.webBeta}
            target="_blank"
            rel="noreferrer"
            className="text-indigo-600 hover:text-indigo-800 hover:bg-white/60 px-2.5 py-1.5 rounded-full font-bold transition-colors duration-300 text-sm whitespace-nowrap"
          >
            网页版 Beta
          </a>
          <button
            type="button"
            onClick={() => handleTabClick('overview', 'download')}
            className="bg-indigo-600 hover:bg-indigo-700 text-white px-5 h-10 rounded-full font-bold transition-all shadow-lg shadow-indigo-500/30 hover:-translate-y-0.5 active:scale-95 text-sm whitespace-nowrap cursor-pointer"
          >
            免费获取
          </button>
        </div>

        {/* 移动端右侧胶囊 */}
        <div
          className={`lg:hidden flex items-center gap-2 pl-3.5 pr-1.5 h-12 rounded-full pointer-events-auto transition-all duration-500 ${pillSurface}`}
        >
          <a
            href={GUIDE_LINKS.webBeta}
            target="_blank"
            rel="noreferrer"
            className="text-indigo-600 font-bold text-xs sm:text-sm px-1.5"
          >
            Web Beta
          </a>
          <button
            type="button"
            onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
            aria-label="切换导航菜单"
            className="p-2 text-slate-700 hover:bg-white/70 rounded-full transition"
          >
            {mobileMenuOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
          </button>
        </div>
      </div>

      {mobileMenuOpen && (
        <div className="lg:hidden mt-2.5 max-w-7xl mx-auto liquid-glass-pill liquid-glass-iridescent rounded-3xl shadow-2xl pointer-events-auto transition-all">
          <div className="px-4 pt-3 pb-5 space-y-1.5">
            {NAV_TABS.map((tab) => {
              const isActive = activeTab === tab.id;
              return (
                <button
                  key={tab.id}
                  type="button"
                  onClick={() => handleTabClick(tab.id)}
                  className={`w-full text-left block px-4 py-3 text-base font-bold rounded-2xl transition ${
                    isActive
                      ? 'bg-indigo-600/10 text-indigo-700 border border-indigo-200/60'
                      : 'text-slate-700 hover:bg-white/60 hover:text-indigo-600'
                  }`}
                >
                  {tab.name}
                </button>
              );
            })}
            <a
              href={GUIDE_LINKS.docsHub}
              target="_blank"
              rel="noreferrer"
              onClick={() => setMobileMenuOpen(false)}
              className="flex items-center gap-2 px-4 py-3 text-base font-bold text-slate-700 hover:bg-white/60 hover:text-indigo-600 rounded-2xl transition"
            >
              <BookOpen className="w-4 h-4" /> 高阶使用指南
            </a>
            <div className="pt-3 pb-1 px-1 flex flex-col gap-2.5">
              <a
                href={GUIDE_LINKS.webBeta}
                target="_blank"
                rel="noreferrer"
                onClick={() => setMobileMenuOpen(false)}
                className="w-full text-center bg-white/75 text-indigo-700 border border-indigo-100 py-3 rounded-2xl font-bold"
              >
                在线体验 Web Beta
              </a>
              <button
                type="button"
                onClick={() => handleTabClick('overview', 'download')}
                className="block w-full text-center bg-indigo-600 text-white py-3 rounded-2xl font-bold shadow-lg shadow-indigo-500/20"
              >
                立即下载
              </button>
            </div>
          </div>
        </div>
      )}
    </nav>
  );
};
