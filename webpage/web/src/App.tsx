import { useState, useEffect } from 'react';
import { LandingPage } from './pages/LandingPage';
import { AuthScreen } from './pages/AuthScreen';
import { WebApp } from './pages/WebApp';
import { ApiService } from './services/api';
import type { User } from './types';
import './index.css';

const App = () => {
  // 1. 核心修改：检测网址后缀，如果是直达链接，跳过 landing
  const [currentView, setCurrentView] = useState<'landing' | 'auth' | 'webapp'>(() => {
    if (window.location.hash.includes('app') || window.location.search.includes('app')) {
      return 'auth';
    }
    return 'landing';
  });

  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    // 检查本地登录态
    const token = ApiService.getToken();
    const savedUser = localStorage.getItem('cdt_user');
    if (token && savedUser) {
      setUser(JSON.parse(savedUser));

      // 2. 核心修改：如果是直达链接且已经登录过，直接进入网页版主界面
      if (window.location.hash.includes('app') || window.location.search.includes('app')) {
        setCurrentView('webapp');
      }
    }
  }, []);

  const handleOpenWeb = () => {
    if (user) {
      setCurrentView('webapp');
    } else {
      setCurrentView('auth');
    }
  };

  const handleLogout = () => {
    ApiService.clearToken();
    localStorage.removeItem('cdt_user');
    setUser(null);
    setCurrentView('landing');
  };

  if (currentView === 'auth') {
    return <AuthScreen onBack={() => setCurrentView('landing')} onLoginSuccess={(u) => { setUser(u); setCurrentView('webapp'); }} />;
  }

  if (currentView === 'webapp' && user) {
    return <WebApp onBack={() => setCurrentView('landing')} user={user} onLogout={handleLogout} />;
  }

  return (
    <div className="bg-white min-h-screen font-sans selection:bg-indigo-600 selection:text-white antialiased">
      <LandingPage onOpenWeb={handleOpenWeb} />
    </div>
  );
};

export default App;