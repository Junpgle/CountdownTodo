import { Monitor, Smartphone, CloudLightning } from 'lucide-react';

export const Features = () => {
  const features = [
    { title: "桌面端 (Win32)", desc: "C++17 原生开发。Layered Window 透明渲染，极低内存占用 (<30MB)，常驻桌面不打扰。", icon: <Monitor className="w-6 h-6" />, color: "bg-blue-50 text-blue-600" },
    { title: "移动端 (Flutter)", desc: "Material 3 规范与沉浸式交互。三级应用分类分析，动态壁纸切换，Android 16 实时通知完美适配。", icon: <Smartphone className="w-6 h-6" />, color: "bg-purple-50 text-purple-600" },
    { title: "云端同步 (D1)", desc: "创新引入 Batch 批量同步与 Delta 增量合并策略。跨设备毫秒级分发，确保极端网络下的数据一致性。", icon: <CloudLightning className="w-6 h-6" />, color: "bg-amber-50 text-amber-600" }
  ];
  return (
    <section id="features" className="py-16 sm:py-24 bg-white">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
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
  );
};
