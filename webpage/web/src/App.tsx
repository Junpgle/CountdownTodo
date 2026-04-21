import { useState, useEffect, lazy, Suspense } from 'react';
import { ApiService } from './services/api';
import type { User } from './types';
import './index.css';

// 懒加载页面组件，启用 Vite 代码分割
const LandingPage = lazy(() => import('./pages/LandingPage').then(m => ({ default: m.LandingPage })));
const AuthScreen = lazy(() => import('./pages/AuthScreen').then(m => ({ default: m.AuthScreen })));
const WebApp = lazy(() => import('./pages/WebApp').then(m => ({ default: m.WebApp })));

// 只有在加载大包时显示的极简 Loading
const LoadingSpinner = () => (
  <div className="min-h-screen flex items-center justify-center bg-slate-50">
    <div className="flex flex-col items-center gap-4">
      <div className="w-10 h-10 border-4 border-indigo-200 border-t-indigo-600 rounded-full animate-spin"></div>
      <p className="text-slate-400 font-bold text-sm tracking-widest uppercase">CDT Loading...</p>
    </div>
  </div>
);

const App = () => {
  const [currentView, setCurrentView] = useState<'landing' | 'auth' | 'webapp'>(() => {
    if (window.location.hash.includes('app') || window.location.search.includes('app')) return 'auth';
    return 'landing';
  });

  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    const token = ApiService.getToken();
    const savedUser = localStorage.getItem('cdt_user');
    if (token && savedUser) {
      try {
        const parsedUser = JSON.parse(savedUser);
        setUser(parsedUser);
        if (window.location.hash.includes('app') || window.location.search.includes('app')) {
          setCurrentView('webapp');
        }
      } catch (e) {
        ApiService.clearAuthAndData();
      }
    }
  }, []);

  const handleOpenWeb = () => {
    if (user) setCurrentView('webapp');
    else {
      window.location.hash = 'app';
      setCurrentView('auth');
    }
  };

  /**
   * 修复：登出时彻底清理状态
   */
  const handleLogout = () => {
    ApiService.clearAuthAndData();
    setUser(null);
    window.location.hash = 'app'; // 确保刷新或返回时留在登录页
    setCurrentView('auth');
  };

  return (
    <Suspense fallback={<LoadingSpinner />}>
      {currentView === 'auth' ? (
        <AuthScreen onBack={() => setCurrentView('landing')} onLoginSuccess={(u) => { setUser(u); setCurrentView('webapp'); }} />
      ) : currentView === 'webapp' && user ? (
        <WebApp onBack={() => setCurrentView('landing')} user={user} onLogout={handleLogout} />
      ) : (
        <div className="bg-white min-h-screen font-sans selection:bg-indigo-600 selection:text-white antialiased">
          <LandingPage onOpenWeb={handleOpenWeb} />
        </div>
      )}
    </Suspense>
  );
};

export default App;