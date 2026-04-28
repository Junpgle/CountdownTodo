import React, { useState, useEffect, useCallback } from 'react';
import { ArrowLeft, Mail, Lock, User as UserIcon, ShieldCheck, MessageSquare, Loader2, KeyRound, Globe, AlertCircle } from 'lucide-react';
import { ApiService } from '../services/api';

export interface User {
  id: number;
  username: string;
  email: string;
  tier?: string;
  avatar_url?: string;
}

interface AuthScreenProps {
  onBack: () => void;
  onLoginSuccess: (u: User) => void;
}

type ForgotMode = 'none' | 'email' | 'verify';

export const AuthScreen = ({ onBack, onLoginSuccess }: AuthScreenProps) => {
  const [isLogin, setIsLogin] = useState(true);
  const [awaitingVerification, setAwaitingVerification] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [username, setUsername] = useState('');
  const [verificationCode, setVerificationCode] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const [forgotMode, setForgotMode] = useState<ForgotMode>('none');
  const [resetEmail, setResetEmail] = useState('');
  const [resetCode, setResetCode] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [cooldown, setCooldown] = useState(0);

  useEffect(() => {
    if (cooldown <= 0) return;
    const timer = setInterval(() => {
      setCooldown(prev => {
        if (prev <= 1) {
          clearInterval(timer);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
    return () => clearInterval(timer);
  }, [cooldown > 0]);

  const handleLogin = async () => {
    try {
      if (isLogin) {
        const res = await ApiService.request('/api/auth/login', {
          method: 'POST',
          body: JSON.stringify({ email, password })
        });
        ApiService.setToken(res.token as string);
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
    if (isLogin) {
      await handleLogin();
    } else {
      await handleRegister();
    }
    setLoading(false);
  };

  const toggleMode = () => {
    setIsLogin(!isLogin);
    setAwaitingVerification(false);
    setError('');
    setVerificationCode('');
  };

  const openForgotPassword = useCallback(() => {
    setResetEmail(email);
    setResetCode('');
    setNewPassword('');
    setConfirmPassword('');
    setCooldown(0);
    setForgotMode('email');
    setError('');
  }, [email]);

  const handleSendResetCode = async () => {
    if (cooldown > 0 || !resetEmail.trim()) return;
    setError('');
    setLoading(true);
    try {
      await ApiService.forgotPassword(resetEmail.trim());
      setCooldown(60);
      setForgotMode('verify');
    } catch (err: unknown) {
      if (err instanceof Error) setError(err.message);
      else setError('发送验证码失败，请重试');
    }
    setLoading(false);
  };

  const handleResetPassword = async () => {
    setError('');
    if (!resetCode.trim()) {
      setError('请输入验证码');
      return;
    }
    if (!newPassword || !confirmPassword) {
      setError('请输入新密码并确认');
      return;
    }
    if (newPassword.length < 6) {
      setError('密码长度不能少于 6 位');
      return;
    }
    if (newPassword !== confirmPassword) {
      setError('两次输入的密码不一致');
      return;
    }
    setLoading(true);
    try {
      await ApiService.resetPassword(resetEmail.trim(), resetCode.trim(), newPassword);
      setForgotMode('none');
      setIsLogin(true);
      setEmail(resetEmail.trim());
      setPassword('');
      setError('');
    } catch (err: unknown) {
      if (err instanceof Error) setError(err.message);
      else setError('重置密码失败，请重试');
    }
    setLoading(false);
  };

  const backFromForgot = useCallback(() => {
    setForgotMode('none');
    setError('');
  }, []);

  if (forgotMode !== 'none') {
    return (
      <div className="min-h-screen bg-slate-900 flex items-center justify-center p-4 font-sans text-slate-900">
        <div className="w-full max-w-[440px] bg-white rounded-[2.5rem] p-10 shadow-2xl relative">
          <button
            type="button"
            onClick={backFromForgot}
            className="absolute top-8 left-8 p-2 text-slate-400 hover:text-slate-700 transition"
          >
            <ArrowLeft className="w-6 h-6" />
          </button>

          <div className="mt-8 mb-8 text-center">
            <div className="inline-flex p-4 rounded-3xl bg-indigo-50 text-indigo-600 mb-6">
              <KeyRound className="w-10 h-10" />
            </div>
            <h2 className="text-3xl font-black tracking-tight mb-2 text-slate-900">
              重置密码
            </h2>
            <p className="text-slate-500 font-medium px-4">
              {forgotMode === 'email'
                ? '输入注册时使用的邮箱，我们将发送验证码'
                : '输入验证码并设置新密码'}
            </p>
          </div>

          {error && (
            <div className="mb-6 p-4 bg-rose-50 border-l-4 border-rose-500 text-rose-700 rounded-r-xl text-sm font-bold animate-in fade-in slide-in-from-top-1">
              {error}
            </div>
          )}

          {forgotMode === 'email' ? (
            <div className="space-y-4">
              <div className="relative group">
                <Mail className="absolute left-4 top-4 w-5 h-5 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                <input
                  type="email"
                  required
                  placeholder="注册邮箱"
                  value={resetEmail}
                  onChange={e => setResetEmail(e.target.value)}
                  className="w-full bg-slate-50 border-2 border-slate-100 pl-12 pr-4 py-4 rounded-2xl focus:border-indigo-500 focus:bg-white outline-none transition-all text-slate-900"
                />
              </div>
              <button
                disabled={loading || cooldown > 0}
                type="button"
                onClick={handleSendResetCode}
                className="w-full bg-indigo-600 text-white font-bold py-4 rounded-2xl mt-4 hover:bg-indigo-700 active:scale-[0.98] transition-all shadow-xl shadow-indigo-100 disabled:opacity-50 flex items-center justify-center gap-3 text-lg"
              >
                {loading ? <Loader2 className="w-6 h-6 animate-spin" /> : '发送验证码'}
              </button>
            </div>
          ) : (
            <div className="space-y-4">
              <div className="relative group">
                <Mail className="absolute left-4 top-4 w-5 h-5 text-slate-400" />
                <input
                  type="email"
                  value={resetEmail}
                  disabled
                  className="w-full bg-slate-50 border-2 border-slate-100 pl-12 pr-4 py-4 rounded-2xl outline-none text-slate-500 cursor-not-allowed"
                />
              </div>
              <div className="relative group">
                <MessageSquare className="absolute left-4 top-4 w-5 h-5 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                <input
                  type="text"
                  required
                  maxLength={6}
                  placeholder="请输入验证码"
                  value={resetCode}
                  onChange={e => setResetCode(e.target.value)}
                  className="w-full bg-slate-50 border-2 border-slate-100 pl-12 pr-4 py-4 rounded-2xl focus:border-indigo-500 focus:bg-white outline-none text-center text-2xl font-mono tracking-[0.5em] transition-all"
                />
              </div>
              <div className="relative group">
                <Lock className="absolute left-4 top-4 w-5 h-5 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                <input
                  type="password"
                  required
                  placeholder="新密码（至少6位）"
                  value={newPassword}
                  onChange={e => setNewPassword(e.target.value)}
                  className="w-full bg-slate-50 border-2 border-slate-100 pl-12 pr-4 py-4 rounded-2xl focus:border-indigo-500 focus:bg-white outline-none transition-all text-slate-900"
                />
              </div>
              <div className="relative group">
                <Lock className="absolute left-4 top-4 w-5 h-5 text-slate-400 group-focus-within:text-indigo-500 transition-colors" />
                <input
                  type="password"
                  required
                  placeholder="确认新密码"
                  value={confirmPassword}
                  onChange={e => setConfirmPassword(e.target.value)}
                  className="w-full bg-slate-50 border-2 border-slate-100 pl-12 pr-4 py-4 rounded-2xl focus:border-indigo-500 focus:bg-white outline-none transition-all text-slate-900"
                />
              </div>
              <button
                disabled={loading}
                type="button"
                onClick={handleResetPassword}
                className="w-full bg-indigo-600 text-white font-bold py-4 rounded-2xl mt-4 hover:bg-indigo-700 active:scale-[0.98] transition-all shadow-xl shadow-indigo-100 disabled:opacity-50 flex items-center justify-center gap-3 text-lg"
              >
                {loading ? <Loader2 className="w-6 h-6 animate-spin" /> : '重置密码'}
              </button>
            </div>
          )}

          <div className="mt-8 text-center">
            <button
              type="button"
              onClick={backFromForgot}
              className="text-indigo-600 font-bold hover:underline"
            >
              ← 返回登录
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-slate-900 flex items-center justify-center p-4 lg:p-8 font-sans text-slate-900 overflow-y-auto">
      <div className="w-full max-w-6xl bg-white rounded-[2.5rem] shadow-2xl flex flex-col lg:flex-row overflow-hidden min-h-[600px]">
        
        {/* 左侧：产品简短介绍 */}
        <div className="lg:w-1/2 bg-gradient-to-br from-indigo-600 to-blue-700 p-10 lg:p-16 text-white flex flex-col justify-between relative overflow-hidden">
          <div className="absolute top-0 left-0 w-full h-full opacity-10">
             <div className="absolute top-[-10%] left-[-10%] w-[50%] h-[50%] rounded-full bg-white blur-[100px]" />
             <div className="absolute bottom-[-10%] right-[-10%] w-[50%] h-[50%] rounded-full bg-indigo-400 blur-[100px]" />
          </div>

          <div className="relative z-10">
            <div className="flex items-center gap-3 mb-8">
               <div className="w-12 h-12 bg-white/20 backdrop-blur-xl rounded-2xl flex items-center justify-center border border-white/30">
                  <span className="text-2xl font-black italic">CDT</span>
               </div>
               <h1 className="text-2xl font-black tracking-tighter">CountDownTodo</h1>
            </div>

            <h2 className="text-4xl lg:text-5xl font-black tracking-tight leading-[1.1] mb-6">
               不仅是待办，<br />更是你的<span className="text-indigo-200">效率引擎</span>。
            </h2>

            <div className="space-y-6">
               <div className="flex items-start gap-4 group">
                  <div className="p-3 rounded-2xl bg-white/10 border border-white/10 group-hover:bg-white/20 transition-all shrink-0">
                    <Globe className="w-6 h-6" />
                  </div>
                  <div>
                    <h3 className="font-bold text-lg">全平台实时同步</h3>
                    <p className="text-indigo-100/60 text-sm">Windows、Android、Web端数据无缝流转，随时随地掌控节奏。</p>
                  </div>
               </div>

               <div className="flex items-start gap-4 group">
                  <div className="p-3 rounded-2xl bg-white/10 border border-white/10 group-hover:bg-white/20 transition-all shrink-0">
                    <ShieldCheck className="w-6 h-6" />
                  </div>
                  <div>
                    <h3 className="font-bold text-lg">团队作战指挥</h3>
                    <p className="text-indigo-100/60 text-sm">专为团队设计的看板模式，实时掌握每一位成员的执行动态。</p>
                  </div>
               </div>

               <div className="flex items-start gap-4 group">
                  <div className="p-3 rounded-2xl bg-white/10 border border-white/10 group-hover:bg-white/20 transition-all shrink-0">
                    <MessageSquare className="w-6 h-6" />
                  </div>
                  <div>
                    <h3 className="font-bold text-lg">视觉化进度管理</h3>
                    <p className="text-indigo-100/60 text-sm">通过甘特图与时间流，让未来变得清晰可见，告别截止日期焦虑。</p>
                  </div>
               </div>
            </div>
          </div>

          <div className="relative z-10 mt-12">
             <button 
               onClick={() => window.location.href = './home.html'}
               className="group flex items-center gap-3 px-8 py-4 rounded-2xl bg-white text-indigo-600 hover:bg-indigo-50 transition-all font-black shadow-lg shadow-black/20 hover:shadow-xl hover:-translate-y-1 active:scale-95 relative overflow-hidden"
             >
                <div className="absolute inset-0 bg-gradient-to-r from-indigo-100 to-transparent opacity-0 group-hover:opacity-20 transition-opacity" />
                <span className="relative z-10">探索完整功能介绍</span>
                <ArrowLeft className="w-5 h-5 rotate-180 group-hover:translate-x-1.5 transition-transform relative z-10" />
                
                {/* 呼吸动画外圈 */}
                <div className="absolute -inset-1 rounded-2xl bg-white/20 animate-pulse -z-10" />
             </button>
          </div>
        </div>

        {/* 右侧：登录/注册表单 */}
        <div className="lg:w-1/2 p-8 lg:p-16 flex flex-col justify-center relative">
          <button
            type="button"
            onClick={awaitingVerification ? () => setAwaitingVerification(false) : onBack}
            className="absolute top-8 left-8 p-2 text-slate-400 hover:text-slate-700 transition"
          >
            <ArrowLeft className="w-6 h-6" />
          </button>

          <div className="mb-8">
            <h2 className="text-3xl font-black tracking-tight mb-2 text-slate-900">
              {awaitingVerification ? '确认您的身份' : (isLogin ? '欢迎回来' : '开始提升效率')}
            </h2>
            <p className="text-slate-500 font-medium">
              {awaitingVerification ? '请输入发送至您邮箱的 6 位验证码' : (isLogin ? '继续同步您的跨端进度' : '加入 50,000+ 效率达人的行列')}
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
                  onChange={setVerificationCode}
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
                <div>
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
                  {isLogin && (
                    <div className="text-right mt-2">
                      <button
                        type="button"
                        onClick={openForgotPassword}
                        className="text-sm text-indigo-600 font-medium hover:underline"
                      >
                        忘记密码？
                      </button>
                    </div>
                  )}
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

          <div className="mt-8 pt-6 border-t border-slate-100 flex items-center justify-between gap-4">
             <div className="flex-1">
                <div className="text-xs text-slate-400 font-bold uppercase tracking-widest mb-1">选择服务器</div>
                <div className="flex gap-2">
                   <button 
                     onClick={() => { ApiService.setBackend('aliyun'); window.location.reload(); }}
                     className={`px-3 py-1.5 rounded-lg text-xs font-bold border transition-all ${ApiService.getBackendKey() === 'aliyun' ? 'bg-indigo-50 border-indigo-200 text-indigo-700' : 'bg-slate-50 border-slate-100 text-slate-400'}`}
                   >
                     阿里云
                   </button>
                   <button 
                     onClick={() => { ApiService.setBackend('cloudflare'); window.location.reload(); }}
                     className={`px-3 py-1.5 rounded-lg text-xs font-bold border transition-all ${ApiService.getBackendKey() === 'cloudflare' ? 'bg-indigo-50 border-indigo-200 text-indigo-700' : 'bg-slate-50 border-slate-100 text-slate-400'}`}
                   >
                     Cloudflare
                   </button>
                </div>
             </div>
             <div className="p-2 rounded-xl bg-amber-50 border border-amber-100 max-w-[200px]">
                <p className="text-[9px] leading-tight text-amber-700 font-medium">推荐使用阿里云以获得更稳定的同步体验。</p>
             </div>
          </div>
        </div>
      </div>
    </div>
  );
};