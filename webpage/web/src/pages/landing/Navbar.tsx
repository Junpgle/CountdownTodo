import { useState, useEffect } from 'react';
import { Layers, Menu, X } from 'lucide-react';

export const Navbar = () => {
  const [isScrolled, setIsScrolled] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  useEffect(() => {
    const handleScroll = () => setIsScrolled(window.scrollY > 20);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const navLinks = [
    { name: '核心特性', href: '#features' },
    { name: '协作与搜索', href: '#collaboration-search' },
    { name: '局域网同步', href: '#lan-sync' },
    { name: '平台体验', href: '#desktop' },
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
            <a href="#download" className="text-indigo-600 hover:text-indigo-800 font-bold transition-colors duration-300 text-sm xl:text-base">网页版入口</a>
            <a href="#download" className="bg-indigo-600 hover:bg-indigo-700 text-white px-5 lg:px-6 py-2 sm:py-2.5 rounded-full font-bold transition-all shadow-lg shadow-indigo-500/30 hover:-translate-y-0.5 active:scale-95">免费获取</a>
          </div>

          <div className="lg:hidden flex items-center gap-4">
            <a href="#download" className="text-indigo-600 font-bold text-sm">网页版</a>
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
              <a href="#download" onClick={() => setMobileMenuOpen(false)} className="w-full text-center bg-indigo-50 text-indigo-700 border border-indigo-100 py-3.5 rounded-xl font-bold">在线体验网页版</a>
              <a href="#download" onClick={() => setMobileMenuOpen(false)} className="block w-full text-center bg-indigo-600 text-white py-3.5 rounded-xl font-bold shadow-lg shadow-indigo-500/20">立即下载</a>
            </div>
          </div>
        </div>
      )}
    </nav>
  );
};
