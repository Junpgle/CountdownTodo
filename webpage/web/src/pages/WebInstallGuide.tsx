import { ArrowLeft, Monitor, Smartphone, CheckCircle2, Zap, Info } from 'lucide-react';

export const WebInstallGuide = ({ onBack }: { onBack: () => void }) => {
    return (
        <div className="min-h-screen bg-slate-50 font-sans selection:bg-indigo-500 selection:text-white">
            {/* 顶部导航 */}
            <header className="bg-white/80 backdrop-blur-md border-b border-slate-200 sticky top-0 z-50">
                <div className="max-w-4xl mx-auto px-6 h-16 sm:h-20 flex items-center gap-4">
                    <button onClick={onBack} className="p-2 hover:bg-slate-100 rounded-full transition text-slate-500">
                        <ArrowLeft className="w-6 h-6" />
                    </button>
                    <h1 className="text-xl font-black text-slate-900">网页版安装指南 (PWA)</h1>
                </div>
            </header>

            <main className="max-w-4xl mx-auto px-6 py-12">
                {/* 概览介绍 */}
                <div className="bg-indigo-600 rounded-[2.5rem] p-8 sm:p-12 text-white mb-12 shadow-xl shadow-indigo-500/20 relative overflow-hidden">
                    <div className="absolute right-0 bottom-0 opacity-10">
                        <Zap className="w-64 h-64" />
                    </div>
                    <div className="relative z-10">
                        <h2 className="text-3xl sm:text-4xl font-black mb-4">什么是 PWA 安装？</h2>
                        <p className="text-indigo-100 text-lg leading-relaxed max-w-2xl">
                            CountDownTodo 网页版采用了渐进式 Web 应用 (PWA) 技术。您可以直接将网页“安装”到桌面或手机主屏上。
                            它将拥有<strong>独立的图标、全屏沉浸感、以及极速的启动体验</strong>，几乎与原生 App 无异。
                        </p>
                    </div>
                </div>

                <div className="grid gap-16">
                    {/* PC 端安装教程 */}
                    <section id="pc-guide">
                        <div className="flex items-center gap-3 mb-8">
                            <div className="w-12 h-12 bg-blue-100 text-blue-600 rounded-2xl flex items-center justify-center">
                                <Monitor className="w-7 h-7" />
                            </div>
                            <div>
                                <h3 className="text-2xl font-black text-slate-900">在电脑端安装 (Windows/Mac)</h3>
                                <p className="text-slate-500 font-medium">推荐使用 Microsoft Edge 或 Google Chrome 浏览器</p>
                            </div>
                        </div>

                        <div className="bg-white rounded-[2rem] border border-slate-200 shadow-sm p-4 sm:p-8">
                            <div className="space-y-8">
                                <div className="flex flex-col md:flex-row gap-8 items-start">
                                    <div className="flex-1 space-y-4 pt-4">
                                        <div className="flex gap-4 items-start">
                                            <span className="w-8 h-8 bg-slate-900 text-white rounded-full flex items-center justify-center shrink-0 font-black text-sm">1</span>
                                            <p className="text-slate-700 font-bold pt-1">点击浏览器右上角的 “三个点 (...)” 菜单按钮。</p>
                                        </div>
                                        <div className="flex gap-4 items-start">
                                            <span className="w-8 h-8 bg-slate-900 text-white rounded-full flex items-center justify-center shrink-0 font-black text-sm">2</span>
                                            <p className="text-slate-700 font-bold pt-1">找到并展开 <span className="bg-yellow-100 px-1 rounded text-yellow-800">“应用”</span> 选项。</p>
                                        </div>
                                        <div className="flex gap-4 items-start">
                                            <span className="w-8 h-8 bg-slate-900 text-white rounded-full flex items-center justify-center shrink-0 font-black text-sm">3</span>
                                            <p className="text-slate-700 font-bold pt-1">点击 <span className="bg-indigo-50 px-1 rounded text-indigo-700">“将此站点作为应用安装”</span>。</p>
                                        </div>
                                    </div>
                                    <div className="flex-1 group">
                                        <div className="rounded-2xl overflow-hidden border border-slate-200 shadow-2xl group-hover:scale-[1.02] transition-transform">
                                            <img src="./web-install-pc.webp" alt="PC 安装演示" className="w-full" />
                                        </div>
                                        <p className="text-xs text-slate-400 mt-4 text-center italic">以 Microsoft Edge 浏览器为例</p>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </section>

                    {/* 移动端安装教程 */}
                    <section id="mobile-guide">
                        <div className="flex items-center gap-3 mb-8">
                            <div className="w-12 h-12 bg-purple-100 text-purple-600 rounded-2xl flex items-center justify-center">
                                <Smartphone className="w-7 h-7" />
                            </div>
                            <div>
                                <h3 className="text-2xl font-black text-slate-900">在手机端安装 (iOS/Android)</h3>
                                <p className="text-slate-500 font-medium">推荐使用 Safari (iOS) 或 Chrome (Android)</p>
                            </div>
                        </div>

                        <div className="bg-white rounded-[2rem] border border-slate-200 shadow-sm p-4 sm:p-8">
                            <div className="flex flex-col md:flex-row gap-10 items-center">
                                <div className="w-full md:w-5/12">
                                    <div className="rounded-[2.5rem] overflow-hidden border-[6px] border-slate-900 shadow-2xl bg-black aspect-[9/19.5]">
                                        <video src="./web-install-phone.mp4" className="w-full h-full object-cover" autoPlay loop muted playsInline />
                                    </div>
                                </div>
                                <div className="flex-1 space-y-6">
                                    <div className="bg-slate-50 p-6 rounded-2xl border border-slate-100">
                                        <h4 className="font-black text-slate-900 mb-3 flex items-center gap-2">
                                            <CheckCircle2 className="w-5 h-5 text-indigo-600" /> iOS (Safari)
                                        </h4>
                                        <p className="text-slate-600 text-sm leading-relaxed">
                                            在 Safari 中打开网页版，点击底部工具栏的“分享”按钮（向上箭头），向下滚动并选择<strong>“添加至主屏幕”</strong>。
                                        </p>
                                    </div>
                                    <div className="bg-slate-50 p-6 rounded-2xl border border-slate-100">
                                        <h4 className="font-black text-slate-900 mb-3 flex items-center gap-2">
                                            <CheckCircle2 className="w-5 h-5 text-indigo-600" /> Android (Chrome)
                                        </h4>
                                        <p className="text-slate-600 text-sm leading-relaxed">
                                            点击浏览器右上角的三个点，选择<strong>“安装应用”</strong>。随后桌面就会出现独立的 App 图标。
                                        </p>
                                    </div>
                                    <div className="p-4 bg-amber-50 rounded-xl border border-amber-100 flex gap-3 text-amber-700">
                                        <Info className="w-5 h-5 shrink-0" />
                                        <p className="text-xs font-bold leading-relaxed">安装后，网页版将拥有独立的窗口管理，不会再与浏览器标签页混在一起，极大提升专注度。</p>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </section>
                </div>

                <div className="mt-20 text-center">
                    <button onClick={onBack} className="bg-slate-900 text-white px-10 py-4 rounded-2xl font-black hover:bg-slate-800 transition active:scale-95 shadow-xl shadow-slate-900/10">
                        我已经明白了，立即去安装
                    </button>
                </div>
            </main>

            <footer className="py-12 border-t border-slate-200 text-center">
                <p className="text-slate-400 text-sm font-bold">CountDownTodo Web Pro | Powered by PWA Technology</p>
            </footer>
        </div>
    );
};