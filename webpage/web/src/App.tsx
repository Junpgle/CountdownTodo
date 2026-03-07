import React, { useState, useEffect } from 'react';
import { LandingPage } from './pages/LandingPage';
import { AuthScreen } from './pages/AuthScreen';
import { WebApp } from './pages/WebApp';
import { ApiService } from './services/api';
import type { AppInfo, User } from './types';
import './index.css';

const App = () => {
  const [currentView, setCurrentView] = useState<'landing' | 'auth' | 'webapp'>('landing');
  const [user, setUser] = useState<User | null>(null);

  // 官网数据
  const [androidInfo, setAndroidInfo] = useState<AppInfo>({ version: '', url: '', desc: '' });
  const [windowsInfo, setWindowsInfo] = useState<AppInfo>({ version: '', url: '', desc: '' });

  useEffect(() => {
    // 检查本地登录态
    const token = ApiService.getToken();
    const savedUser = localStorage.getItem('cdt_user');
    if (token && savedUser) {
      setUser(JSON.parse(savedUser));
    }

    // 加载清单
    const fetchManifests = async () => {
      try {
        const [aRes, wRes] = await Promise.all([
          fetch('[https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json](https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json)'),
          fetch('[https://raw.githubusercontent.com/Junpgle/CountDownTodoLite/refs/heads/master/update_manifest.json](https://raw.githubusercontent.com/Junpgle/CountDownTodoLite/refs/heads/master/update_manifest.json)')
        ]);
        const [aData, wData] = await Promise.all([aRes.json(), wRes.json()]);
        setAndroidInfo({ version: aData.version_name, url: aData.update_info.full_package_url, desc: aData.update_info.description });
        setWindowsInfo({ version: wData.version_name, url: wData.update_info.full_package_url, desc: wData.update_info.description });
      } catch (e) { console.error(e); }
    };
    fetchManifests();
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
      <LandingPage
        onOpenWeb={handleOpenWeb}
        androidInfo={androidInfo}
        windowsInfo={windowsInfo}
      />
    </div>
  );
};

export default App;