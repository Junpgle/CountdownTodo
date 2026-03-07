import React, { useState } from 'react';
import { ArrowLeft, Mail, Lock, User as UserIcon, ShieldCheck, MessageSquare, Loader2 } from 'lucide-react';
import { ApiService } from '../services/api';

export interface User {
  id: number;
  username: string;
  email: string;
  [key: string]: any;
}

interface AuthScreenProps {
  onBack: () => void;
  onLoginSuccess: (u: User) => void;
}

export const AuthScreen = ({ onBack, onLoginSuccess }: AuthScreenProps) => {
  const [isLogin, setIsLogin] = useState(true);
  const [awaitingVerification, setAwaitingVerification] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [username, setUsername] = useState('');
  const [verificationCode, setVerificationCode] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleLogin = async () => {
    try {
      if (isLogin) {
        const res = await ApiService.request('/api/auth/login', {
          method: 'POST',
          body: JSON.stringify({ email, password })
        });
        ApiService.setToken(res.token);
        localStorage.setItem('cdt_user', JSON.stringify(res.user));

        // 2. 这里的封装逻辑非常关键：
        // 登录成功后，WebApp 的 SyncEngine 会根据 res.user.id 来读取 ${id}_todos。
        // 如果该 ID 是第一次登录这台电脑，本地数据自然是空的，会从云端拉取，完美解决串号问题。

        if (onLoginSuccess) onLoginSuccess(res.user as User);
      }
    } catch (err: unknown) {
      if (err instanceof Error) setError(err.message);
      else setError('登录失败，请重试');
    }
  };

  const handleRegister = async () => {
    try {
      const payload = {
        username,
        email,
        password,
        code: awaitingVerification ? verificationCode : null
      };

      const res = await ApiService.register(payload);

      if (res.success) {
        if (res.require_verify && !awaitingVerification) {
          setAwaitingVerification(true);
          setError('');
        } else {
          await handleLogin();
        }
      }
    } catch (err: unknown) {
      if (err instanceof Error) setError(err.message);
      else setError('注册过程中发生未知错误');
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    isLogin ? await handleLogin() : await handleRegister();
    setLoading(false);
  };

  const toggleMode = () => {
    setIsLogin(!isLogin);
    setAwaitingVerification(false);
    setError('');
    setVerificationCode('');
  };

  return (
    <div className="min-h-screen bg-slate-900 flex items-center justify-center p-4 font-sans text-slate-900">
      <div className="w-full max-w-[440px] bg-white rounded-[2.5rem] p-10 shadow-2xl relative">
        <button
          type="button"
          onClick={awaitingVerification ? () => setAwaitingVerification(false) : onBack}
          className="absolute top-8 left-8 p-2 text-slate-400 hover:text-slate-700 transition"
        >
          <ArrowLeft className="w-6 h-6" />
        </button>

        <div className="mt-8 mb-8 text-center">
          <div className="inline-flex p-4 rounded-3xl bg-indigo-50 text-indigo-600 mb-6">
            {awaitingVerification ? <ShieldCheck className="w-10 h-10" /> : (isLogin ? <Lock className="w-10 h-10" /> : <UserIcon className="w-10 h-10" />)}
          </div>
          <h2 className="text-3xl font-black tracking-tight mb-2 text-slate-900">
            {awaitingVerification ? '确认您的身份' : (isLogin ? '欢迎回来' : '跨端同步')}
          </h2>
          <p className="text-slate-500 font-medium px-4">
            {awaitingVerification ? '请输入发送至您邮箱的 6 位验证码' : '登录后即可在各设备间同步进度'}
          </p>
        </div>

        {error && (
          <div className="mb-6 p-4 bg-rose-50 border-l-4 border-rose-500 text-rose-700 rounded-r-xl text-sm font-bold animate-in fade-in slide-in-from-top-1">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          {awaitingVerification ? (
            <div className="relative">
              <MessageSquare className="absolute left-4 top-4 w-5 h-5 text-slate-400" />
              <input
                type="text"
                required
                maxLength={6}
                placeholder="请输入验证码"
                value={verificationCode}
                onChange={e => setVerificationCode(e.target.value)}
                className="w-full bg-slate-50 border-2 border-slate-100 pl-12 pr-4 py-4 rounded-2xl focus:border-indigo-500 focus:bg-white outline-none text-center text-2xl font-mono tracking-[0.5em] transition-all"
              />
            </div>
          ) : (
            <>
              {!isLogin && (
                <div className="relative group">
                  <UserIcon className="absolute left-4 top-4 w-5 h-5 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                  <input
                    type="text"
                    required
                    placeholder="设置用户名"
                    value={username}
                    onChange={e => setUsername(e.target.value)}
                    className="w-full bg-slate-50 border-2 border-slate-100 pl-12 pr-4 py-4 rounded-2xl focus:border-indigo-500 focus:bg-white outline-none transition-all text-slate-900"
                  />
                </div>
              )}
              <div className="relative group">
                <Mail className="absolute left-4 top-4 w-5 h-5 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                <input
                  type="email"
                  required
                  placeholder="电子邮箱"
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                  className="w-full bg-slate-50 border-2 border-slate-100 pl-12 pr-4 py-4 rounded-2xl focus:border-indigo-500 focus:bg-white outline-none transition-all text-slate-900"
                />
              </div>
              <div className="relative group">
                <Lock className="absolute left-4 top-4 w-5 h-5 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                <input
                  type="password"
                  required
                  placeholder="密码"
                  value={password}
                  onChange={e => setPassword(e.target.value)}
                  className="w-full bg-slate-50 border-2 border-slate-100 pl-12 pr-4 py-4 rounded-2xl focus:border-indigo-500 focus:bg-white outline-none transition-all text-slate-900"
                />
              </div>
            </>
          )}

          <button
            disabled={loading}
            type="submit"
            className="w-full bg-indigo-600 text-white font-bold py-4 rounded-2xl mt-4 hover:bg-indigo-700 active:scale-[0.98] transition-all shadow-xl shadow-indigo-100 disabled:opacity-50 flex items-center justify-center gap-3 text-lg"
          >
            {loading ? <Loader2 className="w-6 h-6 animate-spin" /> : (awaitingVerification ? '完成注册' : (isLogin ? '登录' : '发送验证码'))}
          </button>
        </form>

        <div className="mt-8 text-center">
          <p className="text-slate-500 font-medium">
            {isLogin ? '还没有账号？' : '已经有账号了？'}{' '}
            <button type="button" onClick={toggleMode} className="text-indigo-600 font-bold hover:underline">
              {isLogin ? '立即注册' : '去登录'}
            </button>
          </p>
        </div>
      </div>
    </div>
  );
}