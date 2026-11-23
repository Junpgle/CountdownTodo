import { ArrowRight, Sparkles, CalendarRange, Wallet, MonitorSmartphone } from 'lucide-react';
import type { LandingTabId } from '../../constants/links';

interface OverviewGalleryProps {
  onSelectTab: (tab: LandingTabId, anchorId?: string) => void;
}

export const OverviewGallery = ({ onSelectTab }: OverviewGalleryProps) => {
  const cards: Array<{
    tab: LandingTabId;
    anchorId: string;
    badge: string;
    title: string;
    desc: string;
    icon: React.ReactNode;
    badgeColor: string;
    images: Array<{ src: string; alt: string; className?: string }>;
  }> = [
    {
      tab: 'ai',
      anchorId: 'ai-features',
      badge: 'AI 助手 2.0',
      title: '每日建议 · 语音速记 · 工具查账',
      desc: '结合课表空档与习惯进度主动生成今日建议，支持长按「+」语音速记与思考过程摘要。',
      icon: <Sparkles className="w-4 h-4" />,
      badgeColor: 'bg-indigo-50 text-indigo-700',
      images: [
        { src: './ai_daily_suggestion.jpg', alt: '今日 AI 建议卡片', className: 'w-7/12 rounded-2xl object-cover shadow-md border border-slate-100' },
        { src: './ai_chat_tool_use.jpg', alt: 'AI 工具调用查账单', className: 'w-5/12 rounded-2xl object-cover object-top shadow-md border border-slate-100 max-h-[210px]' },
      ],
    },
    {
      tab: 'planning',
      anchorId: 'timetable',
      badge: '规划与课表',
      title: '周视图课表 · 规划时间块排期',
      desc: '教务导入课表、重叠日程 +N 折叠、午休折叠，以及自动避让课表和固定日程的智能推荐时段。',
      icon: <CalendarRange className="w-4 h-4" />,
      badgeColor: 'bg-sky-50 text-sky-700',
      images: [
        { src: './timetable_desktop_v2.jpg', alt: '大屏周视图课表', className: 'w-8/12 rounded-2xl object-cover shadow-md border border-slate-100' },
        { src: './planning_center.jpg', alt: '新建规划块推荐时段', className: 'w-4/12 rounded-2xl object-cover object-top shadow-md border border-slate-100 max-h-[210px]' },
      ],
    },
    {
      tab: 'finance-growth',
      anchorId: 'finance',
      badge: '记账与成长',
      title: '预算环形图 · 习惯热力图 · 勋章',
      desc: '微信/支付宝账单导入与日历收支透视、四维习惯打卡与 30 天热力图、Liquid Glass 流畅度监控。',
      icon: <Wallet className="w-4 h-4" />,
      badgeColor: 'bg-emerald-50 text-emerald-700',
      images: [
        { src: './finance_overview.jpg', alt: '个人记账报表与环形图', className: 'w-4/12 rounded-2xl object-cover object-top shadow-md border border-slate-100 max-h-[210px]' },
        { src: './habit_analytics_v2.jpg', alt: '习惯中心 30 天热力图', className: 'w-8/12 rounded-2xl object-cover shadow-md border border-slate-100' },
      ],
    },
    {
      tab: 'sync-platforms',
      anchorId: 'windows-island',
      badge: '多端与同步',
      title: '双端灵动岛 · 桌面小组件 · 局域网加密',
      desc: 'macOS / Windows 桌面灵动岛、原生桌面小组件群，以及基于 AES 加密与二维码配对的局域网互传。',
      icon: <MonitorSmartphone className="w-4 h-4" />,
      badgeColor: 'bg-purple-50 text-purple-700',
      images: [
        { src: './macos_island_screenshot.jpg', alt: 'macOS 灵动岛拖放与专注', className: 'w-6/12 rounded-2xl object-cover shadow-md border border-slate-100 max-h-[210px]' },
        { src: './desktop_widgets_v2.jpg', alt: '桌面小组件群', className: 'w-6/12 rounded-2xl object-cover shadow-md border border-slate-100 max-h-[210px]' },
      ],
    },
  ];

  return (
    <section id="overview-gallery" className="cv-auto py-16 sm:py-24 liquid-ambient-bg border-y border-white/60 relative overflow-hidden">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        <div className="text-center mb-14">
          <div className="inline-flex items-center gap-2 px-4 py-1.5 liquid-glass-pill text-indigo-700 rounded-full text-xs font-bold mb-4">
            真实界面实拍预览
          </div>
          <h2 className="text-3xl sm:text-5xl font-black text-slate-900 mb-4 tracking-tight">
            软件长什么样？一眼看尽
          </h2>
          <p className="text-lg text-slate-500 max-w-2xl mx-auto">
            Liquid Glass 液态玻璃质感贯穿全端，点击任意场景卡片即可深入查看完整图文介绍
          </p>
        </div>

        <div className="grid md:grid-cols-2 gap-8">
          {cards.map((card) => (
            <button
              key={card.title}
              type="button"
              onClick={() => onSelectTab(card.tab, card.anchorId)}
              className="text-left group liquid-glass liquid-glass-iridescent rounded-[2.25rem] p-6 sm:p-7 hover:-translate-y-1 transition-all duration-300 flex flex-col justify-between cursor-pointer"
            >
              <div>
                <div className="flex items-center justify-between gap-2 mb-4">
                  <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-bold ${card.badgeColor}`}>
                    {card.icon} {card.badge}
                  </span>
                  <span className="inline-flex items-center gap-1 text-xs font-bold text-indigo-600 opacity-80 group-hover:opacity-100">
                    查看详情 <ArrowRight className="w-3.5 h-3.5 group-hover:translate-x-1 transition-transform" />
                  </span>
                </div>
                <h3 className="text-xl sm:text-2xl font-black text-slate-900 mb-2 group-hover:text-indigo-600 transition-colors">
                  {card.title}
                </h3>
                <p className="text-sm text-slate-500 leading-relaxed mb-6">{card.desc}</p>
              </div>

              <div className="flex items-stretch gap-3 bg-slate-50 rounded-2xl p-3 border border-slate-100">
                {card.images.map((img) => (
                  <img
                    key={img.src}
                    src={img.src}
                    alt={img.alt}
                    loading="lazy"
                    className={img.className}
                  />
                ))}
              </div>
            </button>
          ))}
        </div>
      </div>
    </section>
  );
};
