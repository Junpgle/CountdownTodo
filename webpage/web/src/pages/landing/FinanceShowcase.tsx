import {
  Wallet,
  Upload,
  PieChart,
  CalendarDays,
  Sparkles,
  ArrowLeftRight,
  CheckCircle2,
  Receipt,
} from 'lucide-react';
import { ShowcaseImageSlot } from '../../components/ShowcaseImageSlot';

export const FinanceShowcase = () => {
  const features = [
    {
      icon: <Upload className="w-6 h-6" />,
      badge: 'v7.24 新增',
      badgeColor: 'bg-emerald-100 text-emerald-700',
      iconColor: 'bg-emerald-50 text-emerald-600',
      title: '多平台账单导入 & 账户互转',
      desc: '支持微信（CSV/XLSX）、支付宝（CSV）、银行流水、云闪付及 CSV/JSON/OFX/QIF 批量解析入账；新增「账户互转」不虚增收支总额，支持列表多选批量改分类与删除。',
    },
    {
      icon: <PieChart className="w-6 h-6" />,
      badge: 'v7.23 新增',
      badgeColor: 'bg-indigo-100 text-indigo-700',
      iconColor: 'bg-indigo-50 text-indigo-600',
      title: '预算看板与交互式环形图',
      desc: '概览集成月度累计结余趋势、预算消耗进度、快捷模板与消费节奏洞察；点击支出分类交互式环形图扇区可下钻查看小类占比，全面放开跨月自由回溯。',
    },
    {
      icon: <CalendarDays className="w-6 h-6" />,
      badge: 'v6.3 – v7.22',
      badgeColor: 'bg-amber-100 text-amber-700',
      iconColor: 'bg-amber-50 text-amber-600',
      title: '记账日历、周期账单与借贷预测',
      desc: '日历网格按天透视每日收支与笔数，点击直达当日流水或补记一笔；支持房租/会员周期自动入账、借贷分期还款追踪及未来数月刚性支出预测。',
    },
    {
      icon: <Sparkles className="w-6 h-6" />,
      badge: 'AI 联动',
      badgeColor: 'bg-violet-100 text-violet-700',
      iconColor: 'bg-violet-50 text-violet-600',
      title: '一句话 / 付款截图识账与 Token 账本',
      desc: '自然语言输入或从相册把付款截图分享给 App，自动提取商户与金额生成待确认草案（同图含取餐码时智能分流不混淆）；AI 模型 Token 开销可自动写入个人账本。',
    },
  ];

  return (
    <section id="finance" className="cv-auto py-24 sm:py-36 liquid-ambient-bg relative overflow-hidden">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Header */}
        <div className="text-center max-w-3xl mx-auto mb-16 sm:mb-20">
          <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-emerald-100 text-emerald-700 rounded-full text-sm font-bold mb-6">
            <Wallet className="w-4 h-4" /> 个人记账与 AI 智能账本
          </div>
          <h2 className="text-4xl sm:text-5xl lg:text-6xl font-black text-slate-900 mb-6 tracking-tight leading-tight">
            每一分收支，<br className="sm:hidden" />
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-emerald-600 to-teal-500">
              皆有迹可循
            </span>
          </h2>
          <p className="text-lg sm:text-xl text-slate-500 leading-relaxed">
            不只是手动记一笔。从微信/支付宝一键导入历史流水、日历收支透视、预算与借贷预测，到 AI 截图识账单与 Token 用量自动入账，构建完整且安全的跨端个人财务工作台。
          </p>
        </div>

        {/* Main Content Split */}
        <div className="grid lg:grid-cols-12 gap-12 lg:gap-14 items-center">
          {/* Left: Dual Portrait Screenshots Side-by-Side */}
          <div className="lg:col-span-6 relative">
            <div className="absolute -inset-6 bg-gradient-to-tr from-emerald-500/15 to-teal-400/15 blur-3xl rounded-[3rem] pointer-events-none" />
            <div className="relative grid grid-cols-2 gap-4 sm:gap-6 items-start">
              <div className="rounded-[2rem] bg-white p-2.5 border border-slate-200 shadow-2xl transform hover:-translate-y-1 transition-transform duration-500">
                <ShowcaseImageSlot
                  src="./finance_overview.jpg"
                  alt="个人记账预算看板与交互式支出环形图"
                  fileNameHint="finance_overview.jpg"
                  className="rounded-[1.5rem]"
                  imgClassName="w-full h-auto object-contain rounded-[1.5rem]"
                  fallback={
                    <div className="p-5 bg-gradient-to-br from-white via-slate-50/70 to-emerald-50/40 text-left">
                      <p className="text-[11px] font-bold text-slate-400 uppercase tracking-widest">Finance Overview</p>
                      <h4 className="text-lg font-black text-slate-900 mt-1">本月预算与支出环形图</h4>
                      <div className="mt-4 text-sm text-slate-500">已用预算 42.5% · 实时统计</div>
                    </div>
                  }
                />
                <div className="pt-2.5 pb-1 text-center text-xs font-bold text-slate-600 flex items-center justify-center gap-1.5">
                  <PieChart className="w-3.5 h-3.5 text-emerald-600" /> 报表与预算看板
                </div>
              </div>

              <div className="mt-8 sm:mt-12 rounded-[2rem] bg-white p-2.5 border border-slate-200 shadow-2xl transform hover:-translate-y-1 transition-transform duration-500">
                <ShowcaseImageSlot
                  src="./finance_calendar.jpg"
                  alt="记账日历网格每日收支热力透视"
                  fileNameHint="finance_calendar.jpg"
                  className="rounded-[1.5rem]"
                  imgClassName="w-full h-auto object-contain rounded-[1.5rem]"
                  fallback={
                    <div className="p-5 bg-slate-900 text-white text-left">
                      <div className="flex items-center gap-2 mb-2">
                        <Receipt className="w-4 h-4 text-emerald-400" />
                        <span className="text-sm font-black">账单日历透视</span>
                      </div>
                      <div className="text-xs text-slate-300 flex items-center gap-1">
                        <ArrowLeftRight className="w-3.5 h-3.5 text-emerald-400" /> 每日收支结余热力图
                      </div>
                    </div>
                  }
                />
                <div className="pt-2.5 pb-1 text-center text-xs font-bold text-slate-600 flex items-center justify-center gap-1.5">
                  <CalendarDays className="w-3.5 h-3.5 text-indigo-600" /> 记账日历视图
                </div>
              </div>
            </div>
            <div className="mt-5 flex flex-wrap justify-center gap-2 text-xs font-bold text-slate-500">
              <span className="inline-flex items-center gap-1 px-3 py-1 rounded-full bg-white border border-slate-200 shadow-sm">
                <CheckCircle2 className="w-3.5 h-3.5 text-emerald-500" /> 微信 CSV/XLSX
              </span>
              <span className="inline-flex items-center gap-1 px-3 py-1 rounded-full bg-white border border-slate-200 shadow-sm">
                <CheckCircle2 className="w-3.5 h-3.5 text-sky-500" /> 支付宝 CSV
              </span>
              <span className="inline-flex items-center gap-1 px-3 py-1 rounded-full bg-white border border-slate-200 shadow-sm">
                <ArrowLeftRight className="w-3.5 h-3.5 text-indigo-500" /> 账户互转 &amp; 批量管理
              </span>
            </div>
          </div>

          {/* Right: 4 detailed feature cards */}
          <div className="lg:col-span-6 grid sm:grid-cols-1 gap-5">
            {features.map((f, idx) => (
              <div
                key={idx}
                className="flex gap-5 p-6 sm:p-7 rounded-3xl liquid-glass hover:-translate-y-0.5 transition-all duration-300"
              >
                <div className={`w-13 h-13 ${f.iconColor} rounded-2xl flex items-center justify-center shrink-0`}>
                  {f.icon}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex flex-wrap items-center gap-2.5 mb-2">
                    <h3 className="text-xl font-black text-slate-900">{f.title}</h3>
                    <span className={`px-2.5 py-0.5 rounded-full text-[11px] font-bold ${f.badgeColor}`}>
                      {f.badge}
                    </span>
                  </div>
                  <p className="text-slate-500 text-sm sm:text-base leading-relaxed">{f.desc}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};
