import { useState, useEffect } from 'react';
import { Menu, X, BookOpen } from 'lucide-react';
import { GUIDE_LINKS, type LandingTabId } from '../../constants/links';

interface NavbarProps {
  activeTab: LandingTabId;
  onSelectTab: (tab: LandingTabId, anchorId?: string) => void;
}

export const Navbar = ({ activeTab, onSelectTab }: NavbarProps) => {
  const [isScrolled, setIsScrolled] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  useEffect(() => {
    const handleScroll = () => setIsScrolled(window.scrollY > 20);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const navTabs: Array<{ id: LandingTabId; name: string }> = [
    { id: 'overview', name: '总览' },
    { id: 'ai', name: 'AI 助手 2.0' },
    { id: 'planning', name: '规划与协作' },
    { id: 'finance-growth', name: '记账与成长' },
    { id: 'sync-platforms', name: '多端与同步' },
  ];

  const handleTabClick = (tab: LandingTabId, anchorId?: string) => {
    setMobileMenuOpen(false);
    onSelectTab(tab, anchorId);
  };

  return (
    <nav
      className={`fixed w-full z-50 transition-all duration-500 ${
        isScrolled || activeTab !== 'overview'
          ? 'bg-white/90 backdrop-blur-xl border-b border-slate-200 shadow-sm'
          : 'bg-transparent'
      }`}
    >
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center h-16 sm:h-20">
          <button
            type="button"
            onClick={() => handleTabClick('overview')}
            className="flex items-center gap-2.5 group cursor-pointer shrink-0 text-left"
          >
            <img
              src="./app_icon.webp"
              alt="CountDownTodo"
              className="w-8 h-8 sm:w-9 sm:h-9 rounded-xl shadow-md shadow-blue-500/20 object-contain group-hover:scale-105 transition-transform duration-300"
            />
            <span className="font-bold text-xl sm:text-2xl tracking-tight text-slate-900">CountDownTodo</span>
          </button>

          <div className="hidden lg:flex space-x-2 xl:space-x-3 items-center">
            {navTabs.map((tab) => {
              const isActive = activeTab === tab.id;
              return (
                <button
                  key={tab.id}
                  type="button"
                  onClick={() => handleTabClick(tab.id)}
                  className={`px-3.5 py-2 rounded-full font-semibold transition-all duration-300 text-sm whitespace-nowrap cursor-pointer ${
                    isActive
                      ? 'bg-indigo-50 text-indigo-600 font-bold'
                      : 'text-slate-600 hover:text-indigo-600 hover:bg-slate-50'
                  }`}
                >
                  {tab.name}
                </button>
              );
            })}
            <div className="h-5 w-px bg-slate-200 mx-1"></div>
            <a
              href={GUIDE_LINKS.docsHub}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1.5 px-3 py-2 text-slate-600 hover:text-indigo-600 font-semibold transition-colors duration-300 text-sm whitespace-nowrap"
            >
              <BookOpen className="w-4 h-4" /> 高阶指南
            </a>
            <a
              href={GUIDE_LINKS.webBeta}
              target="_blank"
              rel="noreferrer"
              className="text-indigo-600 hover:text-indigo-800 font-bold transition-colors duration-300 text-sm whitespace-nowrap px-2"
            >
              网页版 Beta
            </a>
            <button
              type="button"
              onClick={() => handleTabClick('overview', 'download')}
              className="bg-indigo-600 hover:bg-indigo-700 text-white px-5 py-2 sm:py-2.5 rounded-full font-bold transition-all shadow-lg shadow-indigo-500/30 hover:-translate-y-0.5 active:scale-95 text-sm whitespace-nowrap cursor-pointer"
            >
              免费获取
            </button>
          </div>

          <div className="lg:hidden flex items-center gap-4">
            <a
              href={GUIDE_LINKS.webBeta}
              target="_blank"
              rel="noreferrer"
              className="text-indigo-600 font-bold text-sm"
            >
              Web Beta
            </a>
            <button
              type="button"
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
              aria-label="切换导航菜单"
              className="p-2 text-slate-600 hover:bg-slate-100 rounded-lg transition"
            >
              {mobileMenuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
            </button>
          </div>
        </div>
      </div>

      {mobileMenuOpen && (
        <div className="lg:hidden bg-white/95 backdrop-blur-2xl border-b border-slate-200 shadow-xl absolute w-full transition-all">
          <div className="px-4 pt-2 pb-6 space-y-1.5">
            {navTabs.map((tab) => {
              const isActive = activeTab === tab.id;
              return (
                <button
                  key={tab.id}
                  type="button"
                  onClick={() => handleTabClick(tab.id)}
                  className={`w-full text-left block px-4 py-3 text-base font-bold rounded-xl transition ${
                    isActive
                      ? 'bg-indigo-50 text-indigo-600'
                      : 'text-slate-700 hover:bg-indigo-50 hover:text-indigo-600'
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
              className="flex items-center gap-2 px-4 py-3 text-base font-bold text-slate-700 hover:bg-indigo-50 hover:text-indigo-600 rounded-xl transition"
            >
              <BookOpen className="w-4 h-4" /> 高阶使用指南
            </a>
            <div className="pt-3 pb-2 px-2 flex flex-col gap-3">
              <a
                href={GUIDE_LINKS.webBeta}
                target="_blank"
                rel="noreferrer"
                onClick={() => setMobileMenuOpen(false)}
                className="w-full text-center bg-indigo-50 text-indigo-700 border border-indigo-100 py-3.5 rounded-xl font-bold"
              >
                在线体验 Web Beta
              </a>
              <button
                type="button"
                onClick={() => handleTabClick('overview', 'download')}
                className="block w-full text-center bg-indigo-600 text-white py-3.5 rounded-xl font-bold shadow-lg shadow-indigo-500/20"
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
