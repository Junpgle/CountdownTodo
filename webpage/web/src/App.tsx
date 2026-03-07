import { useState, useEffect } from 'react';
import { LandingPage } from './pages/LandingPage';
import { AuthScreen } from './pages/AuthScreen';
import { WebApp } from './pages/WebApp';
import { ApiService } from './services/api';
import type { User } from './types';
import './index.css';

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
    else setCurrentView('auth');
  };

  /**
   * 修复：登出时彻底清理状态
   */
  const handleLogout = () => {
    ApiService.clearAuthAndData();
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