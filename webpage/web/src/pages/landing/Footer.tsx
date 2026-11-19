import { GUIDE_LINKS, type LandingTabId } from '../../constants/links';

export const Footer = ({
  onSelectTab,
}: {
  onSelectTab?: (tab: LandingTabId, anchorId?: string) => void;
}) => (
  <footer className="bg-white py-20 border-t border-slate-100 text-center">
    <div className="flex flex-col items-center px-4">
      <div className="flex items-center justify-center gap-2.5 mb-8">
        <img
          src="./app_icon.webp"
          alt="CountDownTodo"
          loading="lazy"
          className="w-9 h-9 rounded-xl shadow-md shadow-blue-500/20 object-contain"
        />
        <span className="font-black text-2xl text-slate-900 tracking-tighter">CountDownTodo</span>
      </div>
      <div className="flex flex-wrap justify-center gap-6 sm:gap-10 mb-10">
        <button
          type="button"
          onClick={() => onSelectTab?.('overview')}
          className="text-slate-400 hover:text-indigo-600 font-bold transition cursor-pointer"
        >
          核心特性
        </button>
        <button
          type="button"
          onClick={() => onSelectTab?.('overview', 'download')}
          className="text-slate-400 hover:text-indigo-600 font-bold transition cursor-pointer"
        >
          获取下载
        </button>
        <a
          href={GUIDE_LINKS.docsHub}
          target="_blank"
          rel="noreferrer"
          className="text-slate-400 hover:text-indigo-600 font-bold transition"
        >
          高阶使用指南
        </a>
        <a
          href={GUIDE_LINKS.webBeta}
          target="_blank"
          rel="noreferrer"
          className="text-slate-400 hover:text-indigo-600 font-bold transition"
        >
          网页版 Beta
        </a>
        <a
          href="https://github.com/Junpgle"
          target="_blank"
          rel="noreferrer"
          className="text-slate-400 hover:text-indigo-600 font-bold transition"
        >
          开发者
        </a>
      </div>
      <p className="text-slate-300 text-xs font-black uppercase tracking-[0.3em] mb-2">Designed for Productivity</p>
      <p className="text-slate-400 text-xs font-bold">© 2026 JUNPGLE. ALL RIGHTS RESERVED.</p>
    </div>
  </footer>
);
