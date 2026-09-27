import { lazy, Suspense } from 'react';
import './index.css';

// 介绍页是这个旧网页入口的唯一页面，避免误进入已停用的旧版 WebApp。
const LandingPage = lazy(() => import('./pages/LandingPage').then(m => ({ default: m.LandingPage })));

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
  return (
    <Suspense fallback={<LoadingSpinner />}>
      <div className="bg-white min-h-screen font-sans selection:bg-indigo-600 selection:text-white antialiased">
        <LandingPage />
      </div>
    </Suspense>
  );
};

export default App;
