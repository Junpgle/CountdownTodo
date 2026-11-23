import {
  BookHeart,
  Layers,
  ShieldCheck,
  Award,
  Sparkles,
  Gauge,
} from 'lucide-react';
import { ShowcaseImageSlot } from '../../components/ShowcaseImageSlot';

export const JournalAndDesignShowcase = () => {
  const highlights = [
    {
      icon: <BookHeart className="w-6 h-6" />,
      badge: 'v5.7 – v7.22',
      iconColor: 'bg-rose-50 text-rose-600',
      badgeColor: 'bg-rose-100 text-rose-700',
      title: '私密日记本 & 独立防误删回收站',
      desc: '图文排版记录每日心情、灵感与复盘随想，支持全局搜索直达；误删日记安全移入独立回收站，完整保留配图附件与时间戳，随时一键无损恢复。',
    },
    {
      icon: <Layers className="w-6 h-6" />,
      badge: 'v6.5 – v7.24',
      iconColor: 'bg-sky-50 text-sky-600',
      badgeColor: 'bg-sky-100 text-sky-700',
      title: 'Liquid Glass 液态玻璃 & 纯黑 OLED',
      desc: '独创玻璃流光与边缘折射质感，支持滑块实时调节透光度、模糊度与遮蔽系数；顶部实时展示 FPS 流畅度与渲染压力评估，并支持纯黑 #000000 OLED 极致省电与低电量优雅降级。',
    },
    {
      icon: <Award className="w-6 h-6" />,
      badge: 'v5.5 – v7.24',
      iconColor: 'bg-amber-50 text-amber-600',
      badgeColor: 'bg-amber-100 text-amber-700',
      title: '功能百宝箱定制 & 勋章墙成就体系',
      desc: '内置「功能探索百宝箱」与新手引导清单，支持侧边栏「功能百宝箱」及首页模块自由拖拽排序与显隐；累计专注与打卡解锁数十枚动态成长勋章。',
    },
    {
      icon: <ShieldCheck className="w-6 h-6" />,
      badge: 'v6.9 – v7.24',
      iconColor: 'bg-emerald-50 text-emerald-600',
      badgeColor: 'bg-emerald-100 text-emerald-700',
      title: '定期自动备份、按域恢复 & 同步健康诊断',
      desc: '支持后台定期保存本地数据快照并一键回滚；导入 JSON 备份可按数据域（待办/课表/记账/习惯/日记）独立勾选并出具分域回执；内置同步健康度水位诊断与重复待办合并去重。',
    },
  ];

  return (
    <section id="journal-design" className="cv-auto py-24 sm:py-36 bg-slate-900 text-white relative overflow-hidden">
      <div className="absolute inset-0 bg-gradient-to-b from-slate-900 via-indigo-950/30 to-slate-900 pointer-events-none" />
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        {/* Header */}
        <div className="text-center max-w-3xl mx-auto mb-16 sm:mb-20">
          <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-white/10 text-indigo-300 rounded-full text-sm font-bold mb-6 border border-white/10">
            <Sparkles className="w-4 h-4" /> 私密日记 · Liquid Glass 美学 · 数据安全
          </div>
          <h2 className="text-4xl sm:text-5xl lg:text-6xl font-black text-white mb-6 tracking-tight leading-tight">
            记录生活灵光，<br className="sm:hidden" />
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-sky-400 via-indigo-300 to-rose-300">
              通透质感与稳固守护
            </span>
          </h2>
          <p className="text-lg sm:text-xl text-slate-400 leading-relaxed">
            从私密图文日记与成就勋章墙，到可微调的 Liquid Glass 液态玻璃、FPS 渲染监控，再到定期自动快照备份与按数据域精准恢复——美学与安全兼得。
          </p>
        </div>

        {/* 4 Highlight cards */}
        <div className="grid md:grid-cols-2 gap-6 mb-14">
          {highlights.map((h, i) => (
            <div
              key={i}
              className="flex gap-5 p-7 rounded-3xl liquid-glass-dark hover:-translate-y-0.5 transition-all duration-300"
            >
              <div className={`w-13 h-13 ${h.iconColor} rounded-2xl flex items-center justify-center shrink-0`}>
                {h.icon}
              </div>
              <div>
                <div className="flex flex-wrap items-center gap-2.5 mb-2">
                  <h3 className="text-xl font-black text-white">{h.title}</h3>
                  <span className={`px-2.5 py-0.5 rounded-full text-[11px] font-bold ${h.badgeColor}`}>
                    {h.badge}
                  </span>
                </div>
                <p className="text-slate-300 text-sm sm:text-base leading-relaxed">{h.desc}</p>
              </div>
            </div>
          ))}
        </div>

        {/* Two Visual Showcase Slots */}
        <div className="grid lg:grid-cols-2 gap-8 items-start">
          {/* Slot 1: Medal Wall */}
          <div className="rounded-[2rem] liquid-glass-dark liquid-glass-iridescent p-6 sm:p-8 flex flex-col items-center">
            <div className="w-full flex items-center justify-between gap-2 mb-5">
              <div className="flex items-center gap-2.5">
                <Award className="w-5 h-5 text-amber-400" />
                <span className="font-black text-lg text-white">勋章成就体系</span>
              </div>
              <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-amber-500/15 text-amber-300 text-xs font-bold border border-amber-400/20">
                <Sparkles className="w-3.5 h-3.5" /> 累计专注与打卡里程碑
              </span>
            </div>
            <div className="w-full max-w-[300px] rounded-[1.75rem] overflow-hidden shadow-2xl border border-white/10">
              <ShowcaseImageSlot
                src="./medal_achievements.jpg"
                alt="勋章成就页预览"
                fileNameHint="medal_achievements.jpg"
                imgClassName="w-full h-auto object-contain"
                fallback={
                  <div className="p-6 text-left bg-slate-900 text-white">
                    <div className="text-sm font-black">勋章成就预览</div>
                  </div>
                }
              />
            </div>
          </div>

          {/* Slot 2: Liquid Glass + FPS */}
          <div className="rounded-[2rem] liquid-glass-dark liquid-glass-iridescent p-6 sm:p-8 flex flex-col items-center">
            <div className="w-full flex items-center justify-between gap-2 mb-5">
              <div className="flex items-center gap-2.5">
                <Gauge className="w-5 h-5 text-sky-400" />
                <span className="font-black text-lg text-white">Liquid Glass &amp; 流畅度压力监控</span>
              </div>
              <span className="inline-flex items-center gap-1 px-3 py-1 rounded-full bg-sky-500/20 text-sky-300 text-xs font-black border border-sky-400/30">
                实时 FPS · 三档性能预设
              </span>
            </div>
            <div className="w-full max-w-[300px] rounded-[1.75rem] overflow-hidden shadow-2xl border border-white/10">
              <ShowcaseImageSlot
                src="./animation_fps_settings.jpg"
                alt="动画设置实时 FPS 与负载压力监控"
                fileNameHint="animation_fps_settings.jpg"
                imgClassName="w-full h-auto object-contain"
                fallback={
                  <div className="p-6 text-left bg-slate-900 text-white">
                    <div className="text-sm font-black">动画与流畅度监控</div>
                  </div>
                }
              />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
