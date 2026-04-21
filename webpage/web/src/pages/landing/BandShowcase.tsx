import { Watch, BarChart3, CalendarDays, ListTodo, RefreshCw, ShieldCheck } from 'lucide-react';

export const BandShowcase = () => (
  <section id="band" className="py-24 sm:py-40 bg-gradient-to-b from-white via-slate-50 to-white relative overflow-hidden">
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">

      {/* 顶部标题区 */}
      <div className="text-center mb-16 sm:mb-24">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-blue-100 text-blue-600 rounded-lg text-sm font-bold uppercase tracking-widest mb-6">
          <Watch className="w-5 h-5" /> Xiaomi Vela Quick App
        </div>
        <h2 className="text-4xl sm:text-5xl lg:text-6xl font-black mb-6 leading-tight tracking-tight text-slate-900">
          手腕上的效率助手
        </h2>
        <p className="text-slate-500 text-lg sm:text-xl max-w-2xl mx-auto leading-relaxed">
          运行在小米手环/手表上的快应用，抬腕即览待办、倒数日与课程表，蓝牙与手机无缝双向同步。
        </p>
      </div>

      {/* 核心功能网格 */}
      <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8 mb-20">
        {[
          {
            icon: <ListTodo className="w-6 h-6" />,
            title: "待办事项",
            desc: "进度条可视化时间流逝，颜色分级（蓝/橙/红/绿）直观反映紧急程度，紧急事项优先排序。",
            color: "bg-blue-50 text-blue-600",
            imagePlaceholder: "./band_todo.webp",
          },
          {
            icon: <CalendarDays className="w-6 h-6" />,
            title: "倒数日",
            desc: "精确到天的目标倒计时，按剩余天数升序排列，重要日子一目了然。",
            color: "bg-purple-50 text-purple-600",
            imagePlaceholder: "./band_countdown.webp",
          },
          {
            icon: <BarChart3 className="w-6 h-6" />,
            title: "课程表",
            desc: "展示今天/明天/后天三天课程，进行中/未开始/已结束状态标签，时间、地点、教师信息齐全。",
            color: "bg-amber-50 text-amber-600",
            imagePlaceholder: "./band_course.webp",
          },
        ].map((f, i) => (
          <div key={i} className="group rounded-3xl bg-white border border-slate-100 shadow-sm hover:shadow-xl transition-all duration-500 overflow-hidden">
            <div className="bg-slate-100 relative flex items-center justify-center py-8">
              <img
                src={f.imagePlaceholder}
                alt={f.title}
                className="max-h-[320px] w-auto object-contain group-hover:scale-105 transition-transform duration-700"
                onError={(e) => {
                  (e.target as HTMLImageElement).style.display = 'none';
                  const parent = (e.target as HTMLImageElement).parentElement;
                  if (parent) {
                    const fallback = document.createElement('div');
                    fallback.className = 'flex flex-col items-center justify-center gap-2 text-slate-400 py-16';
                    fallback.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg><span class="text-xs font-medium">截图占位</span><span class="text-[10px] text-slate-400">${f.imagePlaceholder}</span>`;
                    parent.appendChild(fallback);
                  }
                }}
              />
            </div>
            <div className="p-6">
              <div className={`w-10 h-10 ${f.color} rounded-xl flex items-center justify-center mb-4`}>{f.icon}</div>
              <h3 className="text-xl font-bold text-slate-900 mb-2">{f.title}</h3>
              <p className="text-slate-500 text-sm leading-relaxed">{f.desc}</p>
            </div>
          </div>
        ))}
      </div>

      {/* 同步与架构亮点 */}
      <div className="grid md:grid-cols-2 gap-12 items-center">
        <div>
          <h3 className="text-3xl font-black text-slate-900 mb-6">蓝牙双向同步</h3>
          <p className="text-slate-500 text-lg mb-8 leading-relaxed">
            基于 <code className="px-2 py-0.5 bg-slate-100 rounded text-sm font-mono text-slate-700">system.interconnect</code> 蓝牙通道，手表主动向手机请求数据，分批接收、本地存储。手表端切换待办完成状态后自动回传手机，双向联动。
          </p>
          <ul className="space-y-4">
            {[
              { icon: <RefreshCw className="w-5 h-5 text-blue-500" />, title: "分批传输", desc: "支持 batchNum / totalBatches 分批机制，大数据量不丢包，10 秒超时兜底" },
              { icon: <ShieldCheck className="w-5 h-5 text-blue-500" />, title: "内存优化", desc: "动态导入、GC 手动回收、static 属性标注，在有限内存的手表设备上流畅运行" },
            ].map((item, idx) => (
              <li key={idx} className="flex gap-4">
                <div className="w-10 h-10 rounded-xl bg-blue-50 flex items-center justify-center shrink-0">{item.icon}</div>
                <div>
                  <h4 className="font-bold text-slate-900">{item.title}</h4>
                  <p className="text-slate-500 text-sm">{item.desc}</p>
                </div>
              </li>
            ))}
          </ul>
        </div>

        {/* 手表首页展示 */}
        <div className="rounded-2xl overflow-hidden border border-slate-200 shadow-lg bg-slate-100 flex items-center justify-center group hover:shadow-xl transition-all duration-500">
          <img
            src="./band_home.webp"
            alt="手表首页"
            className="max-h-[400px] w-auto object-contain"
            onError={(e) => {
              (e.target as HTMLImageElement).style.display = 'none';
              const parent = (e.target as HTMLImageElement).parentElement;
              if (parent) {
                const fallback = document.createElement('div');
                fallback.className = 'flex flex-col items-center gap-3 text-slate-400 py-16';
                fallback.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg><span class="text-sm font-medium">手表首页截图</span><span class="text-xs">替换 ./band_home.png</span>`;
                parent.appendChild(fallback);
              }
            }}
          />
        </div>
      </div>

      {/* 兼容性提示 */}
      <div className="mt-16 max-w-3xl mx-auto">
        <div className="flex items-start gap-3 px-5 py-4 bg-amber-50 border border-amber-200 rounded-xl">
          <svg xmlns="http://www.w3.org/2000/svg" className="w-5 h-5 text-amber-600 shrink-0 mt-0.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>
          <div>
            <p className="text-sm font-bold text-amber-800 mb-1">设备兼容性说明</p>
            <p className="text-sm text-amber-700 leading-relaxed">本快应用目前仅基于 <strong>小米手环 9 Pro</strong> 测试验证。其他小米手环/手表设备可能可以安装运行，但因屏幕尺寸差异可能出现布局错乱，请知悉。</p>
          </div>
        </div>
      </div>

    </div>
  </section>
);
