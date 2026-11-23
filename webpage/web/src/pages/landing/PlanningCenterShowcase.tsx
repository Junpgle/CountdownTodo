import {
  CalendarRange,
  Split,
  Gauge,
  CalendarSync,
  RotateCcw,
  Clock,
  AlertCircle,
} from 'lucide-react';
import { ShowcaseImageSlot } from '../../components/ShowcaseImageSlot';

export const PlanningCenterShowcase = () => {
  const pillars = [
    {
      icon: <Split className="w-6 h-6" />,
      badge: '时间块排期',
      iconColor: 'bg-indigo-50 text-indigo-600',
      badgeColor: 'bg-indigo-100 text-indigo-700',
      title: '拖拽排期 & 大任务分段拆分',
      desc: '从待安排池把待办拖拽排入今日或未来几天的具体时段，时间轴按小时动态分轨不挤压；耗时长的大任务一键「拆分」为多个可执行时间块。',
    },
    {
      icon: <Gauge className="w-6 h-6" />,
      badge: 'v6.7 – v7.22',
      iconColor: 'bg-blue-50 text-blue-600',
      badgeColor: 'bg-blue-100 text-blue-700',
      title: '每周空闲预算 & 习惯/挑战软日程联动',
      desc: '自由设定周一至周日的可支配时段，系统自动扣减课程、固定日程以及习惯/30天挑战的「容量规划预留」，实时预警今日是否时间超载。',
    },
    {
      icon: <CalendarSync className="w-6 h-6" />,
      badge: 'v7.22 – v7.23',
      iconColor: 'bg-violet-50 text-violet-600',
      badgeColor: 'bg-violet-100 text-violet-700',
      title: '固定日程双向绑定 & 改期智能复核',
      desc: '管理每周例会、自习或班次，支持独立地点解析（联动小组件展示）与课前/会前「准备时间」预留；日程改期时自动提示复核关联待办截止时间。',
    },
    {
      icon: <RotateCcw className="w-6 h-6" />,
      badge: 'v6.8 – v7.23',
      iconColor: 'bg-amber-50 text-amber-600',
      badgeColor: 'bg-amber-100 text-amber-700',
      title: '执行复盘、漏做恢复 & 时间日志课表映射',
      desc: '直观对比「计划排期时长 vs 番茄钟真实专注时长」，过期漏做规划块支持一键顺延或补标完成；时间日志自动投影课程与固定日程半透明虚线占位。',
    },
  ];

  return (
    <section id="planning" className="cv-auto py-24 sm:py-36 liquid-ambient-bg relative overflow-hidden">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col lg:flex-row items-center gap-14 lg:gap-16">
          {/* Left: Copy + 4 pillars */}
          <div className="flex-1 space-y-8">
            <div>
              <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-indigo-50 text-indigo-700 rounded-full text-sm font-bold mb-6">
                <CalendarRange className="w-4 h-4" /> 规划中心与时间块
              </div>
              <h2 className="text-4xl sm:text-5xl lg:text-6xl font-black text-slate-900 leading-tight tracking-tight mb-6">
                把“要做什么”变成<br />
                <span className="text-transparent bg-clip-text bg-gradient-to-r from-indigo-600 to-blue-500">
                  “几点到几点做”
                </span>
              </h2>
              <p className="text-lg sm:text-xl text-slate-500 leading-relaxed">
                待办清单解决“不忘记”，规划中心解决“能做完”。无缝聚合学校课表、固定日程、待办时间块与习惯软预留，在动笔前先看见真实可用的每一小时。
              </p>
            </div>

            <div className="grid sm:grid-cols-2 gap-5">
              {pillars.map((item, idx) => (
                <div
                  key={idx}
                  className="p-6 rounded-3xl liquid-glass hover:-translate-y-0.5 transition-all duration-300"
                >
                  <div className="flex items-center justify-between mb-4">
                    <div className={`w-11 h-11 ${item.iconColor} rounded-2xl flex items-center justify-center`}>
                      {item.icon}
                    </div>
                    <span className={`px-2.5 py-0.5 rounded-full text-[11px] font-bold ${item.badgeColor}`}>
                      {item.badge}
                    </span>
                  </div>
                  <h3 className="text-lg font-black text-slate-900 mb-2">{item.title}</h3>
                  <p className="text-sm text-slate-500 leading-relaxed">{item.desc}</p>
                </div>
              ))}
            </div>
          </div>

          {/* Right: Visual Showcase Slot */}
          <div className="flex-1 w-full relative flex justify-center">
            <div className="absolute -inset-6 bg-gradient-to-tr from-indigo-500/15 to-sky-400/15 blur-3xl rounded-[3rem] pointer-events-none" />
            <div className="relative w-full max-w-[340px] sm:max-w-[360px] rounded-[2.5rem] liquid-glass liquid-glass-iridescent p-3">
              <ShowcaseImageSlot
                src="./planning_center.jpg"
                alt="规划中心新建规划块与智能推荐时段"
                fileNameHint="planning_center.jpg"
                className="rounded-[2rem]"
                imgClassName="w-full h-auto object-contain rounded-[2rem]"
                fallback={
                  <div className="p-6 sm:p-7 bg-slate-900 text-white rounded-[1.75rem] text-left">
                    {/* Top Budget Bar */}
                    <div className="flex items-center justify-between mb-4 pt-2">
                      <div>
                        <span className="text-[11px] font-bold uppercase tracking-widest text-indigo-300">
                          Today Capacity · 动态容量预算
                        </span>
                        <h4 className="text-lg font-black text-white mt-0.5">今日可支配时段排期</h4>
                      </div>
                      <span className="px-3 py-1 rounded-full bg-emerald-500/20 text-emerald-300 text-xs font-bold border border-emerald-400/30">
                        余 4.0h 可排
                      </span>
                    </div>

                    <div className="p-3.5 rounded-2xl bg-white/5 border border-white/10 mb-5">
                      <div className="flex justify-between text-[11px] text-slate-300 mb-2 font-semibold">
                        <span>总可用 7.5h（扣减课表 2h + 固定日程 1h + 习惯 0.5h）</span>
                        <span className="text-indigo-300">负载 47%</span>
                      </div>
                      <div className="h-2.5 w-full rounded-full bg-white/10 overflow-hidden flex">
                        <div className="w-[26%] bg-sky-400" title="课程占位" />
                        <div className="w-[14%] bg-violet-400" title="固定日程+准备时间" />
                        <div className="w-[7%] bg-emerald-400" title="习惯预留" />
                      </div>
                    </div>

                    {/* Timeline lanes */}
                    <div className="space-y-3 mb-5">
                      <div className="flex items-center gap-3 p-3 rounded-2xl border border-dashed border-sky-400/40 bg-sky-500/10">
                        <span className="text-xs font-mono text-sky-300 w-12 shrink-0">08:00</span>
                        <div className="flex-1 min-w-0">
                          <div className="text-xs font-bold text-white truncate">高等数学 · 逸夫楼 201</div>
                          <div className="text-[11px] text-sky-300/80">课程自动投影占位 · 不可冲突排期</div>
                        </div>
                      </div>

                      <div className="flex items-center gap-3 p-3 rounded-2xl border border-violet-400/30 bg-violet-500/15">
                        <span className="text-xs font-mono text-violet-300 w-12 shrink-0">14:00</span>
                        <div className="flex-1 min-w-0">
                          <div className="text-xs font-bold text-white truncate">项目周例会（含 15m 准备时间）</div>
                          <div className="text-[11px] text-violet-200/80">关联待办：整理迭代演示稿 · 地点：302 会议室</div>
                        </div>
                      </div>

                      <div className="flex items-center gap-3 p-3.5 rounded-2xl bg-gradient-to-r from-indigo-600 to-blue-600 shadow-lg">
                        <span className="text-xs font-mono text-indigo-100 w-12 shrink-0">15:30</span>
                        <div className="flex-1 min-w-0">
                          <div className="text-xs font-black text-white truncate">完成算法刷题复盘（拆分时间块 1/2）</div>
                          <div className="text-[11px] text-indigo-100/90 flex items-center gap-2 mt-0.5">
                            <Clock className="w-3 h-3" /> 计划 60m · 点击直开番茄钟计时
                          </div>
                        </div>
                      </div>

                      <div className="flex items-center gap-3 p-3 rounded-2xl border border-emerald-400/30 bg-emerald-500/10">
                        <span className="text-xs font-mono text-emerald-300 w-12 shrink-0">21:00</span>
                        <div className="flex-1 min-w-0">
                          <div className="text-xs font-bold text-white truncate">深度阅读 30 分钟 · 习惯软日程预留</div>
                          <div className="text-[11px] text-emerald-300/80">专注结束自动盖章落印</div>
                        </div>
                      </div>
                    </div>

                    {/* Execution Review Bar */}
                    <div className="flex flex-wrap items-center justify-between gap-2 p-3.5 rounded-2xl bg-amber-500/10 border border-amber-400/30">
                      <div className="flex items-center gap-2 text-xs text-amber-200 font-semibold">
                        <AlertCircle className="w-4 h-4 text-amber-400 shrink-0" />
                        <span>昨日 1 项漏做规划块 · 计划 vs 实际达成率 91%</span>
                      </div>
                      <span className="px-3 py-1 rounded-xl bg-amber-400 text-slate-950 text-[11px] font-black">
                        一键顺延到今天
                      </span>
                    </div>
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
