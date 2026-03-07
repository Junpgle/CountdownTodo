import React, { useState } from 'react';
import { ArrowLeft, Mail, Lock, User as UserIcon } from 'lucide-react';
import { ApiService } from '../services/api';
import type { User } from '../types';

export const AuthScreen = ({ onBack, onLoginSuccess }: { onBack: () => void, onLoginSuccess: (u: User) => void }) => {
  const [isLogin, setIsLogin] = useState(true);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [username, setUsername] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      if (isLogin) {
        const res = await ApiService.request('/api/auth/login', {
          method: 'POST',
          body: JSON.stringify({ email, password })
        });
        ApiService.setToken(res.token);
        localStorage.setItem('cdt_user', JSON.stringify(res.user));
        onLoginSuccess(res.user);
      } else {
        // 注册简易流程 (需配合后端验证码，这里仅演示发起)
        const res = await ApiService.request('/api/auth/register', {
           method: 'POST',
           body: JSON.stringify({ email, password, username })
        });
        alert(res.message || '注册请求已发送，请检查邮箱验证码（网页版暂不提供完整注册流程，请使用APP注册）');
        setIsLogin(true);
      }
    } catch (err: any) {
      setError(err.message || '操作失败');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-900 flex items-center justify-center p-4">
      <div className="w-full max-w-[420px] bg-slate-50 rounded-[3rem] p-8 shadow-2xl relative overflow-hidden">
         <button onClick={onBack} className="absolute top-6 left-6 p-2 text-slate-400 hover:text-slate-700 transition">
            <ArrowLeft className="w-6 h-6" />
         </button>

         <div className="mt-12 mb-10 text-center">
            <h2 className="text-3xl font-black text-slate-900 mb-2">{isLogin ? '欢迎回来' : '创建账号'}</h2>
            <p className="text-slate-500">连接您的跨端数据</p>
         </div>

         {error && <div className="mb-6 p-3 bg-red-50 text-red-600 rounded-xl text-sm font-bold">{error}</div>}

         <form onSubmit={handleSubmit} className="space-y-4">
            {!isLogin && (
              <div className="relative">
                <UserIcon className="absolute left-4 top-3.5 w-5 h-5 text-slate-400" />
                <input type="text" required placeholder="用户名" value={username} onChange={e=>setUsername(e.target.value)} className="w-full bg-white border border-slate-200 pl-12 pr-4 py-3.5 rounded-2xl focus:ring-2 focus:ring-indigo-500 outline-none" />
              </div>
            )}
            <div className="relative">
              <Mail className="absolute left-4 top-3.5 w-5 h-5 text-slate-400" />
              <input type="email" required placeholder="邮箱地址" value={email} onChange={e=>setEmail(e.target.value)} className="w-full bg-white border border-slate-200 pl-12 pr-4 py-3.5 rounded-2xl focus:ring-2 focus:ring-indigo-500 outline-none" />
            </div>
            <div className="relative">
              <Lock className="absolute left-4 top-3.5 w-5 h-5 text-slate-400" />
              <input type="password" required placeholder="密码" value={password} onChange={e=>setPassword(e.target.value)} className="w-full bg-white border border-slate-200 pl-12 pr-4 py-3.5 rounded-2xl focus:ring-2 focus:ring-indigo-500 outline-none" />
            </div>

            <button disabled={loading} type="submit" className="w-full bg-indigo-600 text-white font-bold py-4 rounded-2xl mt-4 hover:bg-indigo-700 transition shadow-lg shadow-indigo-500/30 disabled:opacity-50">
               {loading ? '处理中...' : (isLogin ? '登录' : '注册')}
            </button>
         </form>

         <div className="mt-8 text-center text-sm">
            <span className="text-slate-500">{isLogin ? '没有账号？' : '已有账号？'} </span>
            <button onClick={() => {setIsLogin(!isLogin); setError('');}} className="text-indigo-600 font-bold hover:underline">
               {isLogin ? '立即注册' : '去登录'}
            </button>
         </div>
      </div>
    </div>
  );
};
