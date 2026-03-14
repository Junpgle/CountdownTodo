import { Layers } from 'lucide-react';

export const Footer = ({ onOpenWeb }: { onOpenWeb: () => void }) => (
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
);
