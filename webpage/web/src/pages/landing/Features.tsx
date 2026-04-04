import { Monitor, Smartphone, CloudLightning, Brain, MessageSquare, BellRing } from 'lucide-react';

export const Features = () => {
  const features = [
    { title: "桌面端 (Win32)", desc: "C++17 原生开发。Layered Window 透明渲染，极低内存占用 (<30MB)，常驻桌面不打扰。", icon: <Monitor className="w-6 h-6" />, color: "bg-blue-50 text-blue-600" },
    { title: "移动端 (Flutter)", desc: "Material 3 规范与沉浸式交互。三级应用分类分析，动态壁纸切换，Android 16 实时通知完美适配。", icon: <Smartphone className="w-6 h-6" />, color: "bg-purple-50 text-purple-600" },
    { title: "云端同步 (D1)", desc: "创新引入 Batch 批量同步与 Delta 增量合并策略。跨设备毫秒级分发，确保极端网络下的数据一致性。", icon: <CloudLightning className="w-6 h-6" />, color: "bg-amber-50 text-amber-600" },
  ];

  return (
    <>
      <section id="features" className="py-16 sm:py-24 bg-white">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold text-slate-900 mb-4">核心特性</h2>
            <p className="text-lg text-slate-500 max-w-2xl mx-auto">跨平台架构，为效率而生</p>
          </div>
          <div className="grid md:grid-cols-3 gap-8">
            {features.map((f, i) => (
              <div key={i} className="p-10 rounded-[2.5rem] bg-slate-50 hover:bg-white hover:shadow-xl transition-all duration-500 group border border-slate-100">
                <div className={`w-14 h-14 ${f.color} rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 transition`}>{f.icon}</div>
                <h3 className="text-2xl font-bold mb-4 text-slate-900">{f.title}</h3>
                <p className="text-slate-500 leading-relaxed text-base">{f.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section id="ai-features" className="py-16 sm:py-24 bg-gradient-to-b from-slate-50 to-white">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold text-slate-900 mb-4">AI 智能识别</h2>
            <p className="text-lg text-slate-500 max-w-2xl mx-auto">大模型驱动，让创建待办变得前所未有的简单</p>
          </div>

          {/* AI 识别过程 */}
          <div className="flex flex-col md:flex-row gap-12 items-center mb-20">
            <div className="flex-1">
              <div className="w-14 h-14 bg-emerald-50 text-emerald-600 rounded-2xl flex items-center justify-center mb-6">
                <Brain className="w-6 h-6" />
              </div>
              <h3 className="text-2xl font-bold mb-4 text-slate-900">AI 大模型识别待办</h3>
              <p className="text-slate-500 leading-relaxed text-base mb-4">
                支持文本与图片双模输入。文字场景：一句话自然语言解析，自动识别时间、地点、重复周期生成结构化待办。图片场景：截图/照片智能识别，自动提取关键信息一键转待办。
              </p>
              <p className="text-slate-500 leading-relaxed text-base">
                特别优化外卖/快递场景，自动识别 KFC、瑞幸、顺丰等数十种品牌的取餐码/取件码，生成标准化待办标题。
              </p>
            </div>
            <div className="flex-1 w-full">
              <div className="rounded-2xl overflow-hidden border border-slate-200 shadow-lg bg-slate-100 aspect-[16/9] flex items-center justify-center group hover:shadow-xl transition-all duration-500">
                <img
                  src="./ai_todo.webp"
                  alt="AI 识别过程"
                  className="w-full h-full object-cover"
                  onError={(e) => {
                    (e.target as HTMLImageElement).style.display = 'none';
                    const parent = (e.target as HTMLImageElement).parentElement;
                    if (parent) {
                      const fallback = document.createElement('div');
                      fallback.className = 'flex flex-col items-center gap-3 text-slate-400';
                      fallback.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg><span class="text-sm font-medium">截图展示区</span><span class="text-xs">替换 ai_todo.webp</span>`;
                      parent.appendChild(fallback);
                    }
                  }}
                />
              </div>
            </div>
          </div>

          {/* 特殊待办上岛 */}
          <div className="flex flex-col md:flex-row-reverse gap-12 items-center mb-20">
            <div className="flex-1">
              <div className="w-14 h-14 bg-rose-50 text-rose-600 rounded-2xl flex items-center justify-center mb-6">
                <BellRing className="w-6 h-6" />
              </div>
              <h3 className="text-2xl font-bold mb-4 text-slate-900">特殊待办灵动岛提醒</h3>
              <p className="text-slate-500 leading-relaxed text-base">
                识别到外卖取餐、快递取件等特殊待办后，自动触发桌面灵动岛通知。取餐码、品牌信息一目了然，无需打开应用即可快速获取关键信息，不错过每一顿热饭。
              </p>
            </div>
            <div className="flex-1 w-full">
              <div className="rounded-2xl overflow-hidden border border-slate-200 shadow-lg bg-slate-100 aspect-[16/9] flex items-center justify-center group hover:shadow-xl transition-all duration-500">
                <img
                  src="./ai_todo_special.webp"
                  alt="特殊待办上岛"
                  className="w-full h-full object-cover"
                  onError={(e) => {
                    (e.target as HTMLImageElement).style.display = 'none';
                    const parent = (e.target as HTMLImageElement).parentElement;
                    if (parent) {
                      const fallback = document.createElement('div');
                      fallback.className = 'flex flex-col items-center gap-3 text-slate-400';
                      fallback.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg><span class="text-sm font-medium">截图展示区</span><span class="text-xs">替换 ai_todo_special.webp</span>`;
                      parent.appendChild(fallback);
                    }
                  }}
                />
              </div>
            </div>
          </div>

          {/* 多模型配置 */}
          <div className="flex flex-col md:flex-row gap-12 items-center">
            <div className="flex-1">
              <div className="w-14 h-14 bg-cyan-50 text-cyan-600 rounded-2xl flex items-center justify-center mb-6">
                <MessageSquare className="w-6 h-6" />
              </div>
              <h3 className="text-2xl font-bold mb-4 text-slate-900">多模型灵活切换</h3>
              <p className="text-slate-500 leading-relaxed text-base mb-4">
                内置智谱 GLM 系列免费/付费模型预设，支持自定义 OpenAI 兼容 Base URL 与模型。
              </p>
              <p className="text-slate-500 leading-relaxed text-base">
                文本模型与视觉模型独立配置，满足不同场景需求。免费模型即可享受 AI 识别能力，付费模型获得更精准的结果。
              </p>
            </div>
            <div className="flex-1 w-full flex justify-center">
              <div className="rounded-2xl overflow-hidden border border-slate-200 shadow-lg bg-slate-100 flex items-center justify-center group hover:shadow-xl transition-all duration-500">
                <img
                  src="./ai_model_config.webp"
                  alt="大模型配置界面"
                  className="max-h-[600px] w-auto object-contain"
                  onError={(e) => {
                    (e.target as HTMLImageElement).style.display = 'none';
                    const parent = (e.target as HTMLImageElement).parentElement;
                    if (parent) {
                      const fallback = document.createElement('div');
                      fallback.className = 'flex flex-col items-center gap-3 text-slate-400 py-16';
                      fallback.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg><span class="text-sm font-medium">截图展示区</span><span class="text-xs">替换 ai_model_config.webp</span>`;
                      parent.appendChild(fallback);
                    }
                  }}
                />
              </div>
            </div>
          </div>
        </div>
      </section>
    </>
  );
};
