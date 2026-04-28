import { useState, useEffect, lazy, Suspense } from 'react';
import { ApiService } from './services/api';
import type { User } from './types';
import './index.css';

// 懒加载页面组件，启用 Vite 代码分割
const LandingPage = lazy(() => import('./pages/LandingPage').then(m => ({ default: m.LandingPage })));
const AuthScreen = lazy(() => import('./pages/AuthScreen').then(m => ({ default: m.AuthScreen })));
const WebApp = lazy(() => import('./pages/WebApp').then(m => ({ default: m.WebApp })));
import TeamDisplayBoard from './pages/TeamDisplayBoard';

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
  const isAppPage = !window.location.pathname.includes('home.html');
  
  const [currentView, setCurrentView] = useState<'landing' | 'auth' | 'webapp' | 'dashboard'>(() => {
    if (!isAppPage) return 'landing';
    if (window.location.hash.includes('dashboard')) return 'dashboard';
    return ApiService.getToken() ? 'webapp' : 'auth';
  });

  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    if (!isAppPage && currentView !== 'landing') {
        window.location.href = './index.html' + window.location.hash;
        return;
    }

    const handleHashChange = () => {
      const hash = window.location.hash;
      if (hash.includes('dashboard')) {
        setCurrentView('dashboard');
      } else if (hash.includes('app')) {
        setCurrentView(ApiService.getToken() ? 'webapp' : 'auth');
      }
    };
    if (isAppPage) {
        window.addEventListener('hashchange', handleHashChange);
    }

    const token = ApiService.getToken();
    const savedUser = localStorage.getItem('cdt_user');
    if (token && savedUser) {
      try {
        const parsedUser = JSON.parse(savedUser);
        setUser(parsedUser);
        if (isAppPage && currentView === 'auth') {
          setCurrentView('webapp');
        }
      } catch (e) {
        ApiService.clearAuthAndData();
      }
    }

    return () => window.removeEventListener('hashchange', handleHashChange);
  }, [isAppPage, currentView]);

  const handleOpenWeb = () => {
    window.location.href = './index.html#app';
  };

  const handleLogout = () => {
    ApiService.clearAuthAndData();
    setUser(null);
    setCurrentView('auth');
  };

  return (
    <Suspense fallback={<LoadingSpinner />}>
      {isAppPage ? (
          <>
            {currentView === 'dashboard' ? (
                <TeamDisplayBoard user={user} onBack={() => setCurrentView('webapp')} />
            ) : currentView === 'auth' ? (
                <AuthScreen onBack={() => { window.location.href = './home.html'; }} onLoginSuccess={(u) => { setUser(u); setCurrentView('webapp'); }} />
            ) : currentView === 'webapp' && user ? (
                <WebApp onBack={() => { window.location.href = './home.html'; }} onOpenDashboard={() => setCurrentView('dashboard')} user={user} onLogout={handleLogout} />
            ) : (
                <LoadingSpinner />
            )}
          </>
      ) : (
        <div className="bg-white min-h-screen font-sans selection:bg-indigo-600 selection:text-white antialiased">
          <LandingPage onOpenWeb={handleOpenWeb} />
        </div>
      )}
    </Suspense>
  );
};

export default App;