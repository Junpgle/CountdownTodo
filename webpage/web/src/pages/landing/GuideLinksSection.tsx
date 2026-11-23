import { BookOpen, Sparkles, LayoutGrid, Watch, Globe, ExternalLink } from 'lucide-react';
import { GUIDE_LINKS } from '../../constants/links';

export const GuideLinksSection = ({
  onShowInstallGuide,
}: {
  onShowInstallGuide: () => void;
}) => {
  const guides = [
    {
      title: 'CountDownTodo 官方文档合集',
      desc: '完整功能使用手册与常见问题解答，持续同步最新版本特性。',
      href: GUIDE_LINKS.docsHub,
      icon: <BookOpen className="w-6 h-6" />,
      color: 'bg-indigo-50 text-indigo-600',
      tag: '腾讯文档',
    },
    {
      title: 'AI 智能助手高阶使用指南',
      desc: '涵盖大模型 API 配置、语音速记、图片识别、取餐码上岛与工具调用技巧。',
      href: GUIDE_LINKS.aiAssistantAdvanced,
      icon: <Sparkles className="w-6 h-6" />,
      color: 'bg-emerald-50 text-emerald-600',
      tag: '高阶教程',
    },
    {
      title: '桌面小部件与灵动特性教程',
      desc: '详解 Android 桌面/平板小部件配置、待办地点与近期账单展示方式。',
      href: GUIDE_LINKS.widgetFeatures,
      icon: <LayoutGrid className="w-6 h-6" />,
      color: 'bg-purple-50 text-purple-600',
      tag: '高阶教程',
    },
    {
      title: '小米手环快应用安装与 FAQ',
      desc: 'BandBBS 帖子：涵盖小米手环 9 Pro 安装步骤、蓝牙双向同步与常见问题。',
      href: GUIDE_LINKS.bandGuide,
      icon: <Watch className="w-6 h-6" />,
      color: 'bg-teal-50 text-teal-600',
      tag: '穿戴端指南',
    },
  ];

  return (
    <section id="guides" className="cv-auto py-16 sm:py-24 liquid-ambient-bg border-y border-white/60">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col md:flex-row md:items-end justify-between gap-6 mb-12">
          <div>
            <div className="inline-flex items-center gap-2 px-3.5 py-1 liquid-glass-pill text-indigo-700 rounded-full text-xs font-bold mb-4">
              <BookOpen className="w-4 h-4" /> 高阶使用指南与文档
            </div>
            <h2 className="text-3xl sm:text-4xl font-black text-slate-900 tracking-tight">
              玩转隐藏技巧，上手更进一步
            </h2>
          </div>
          <button
            onClick={onShowInstallGuide}
            className="inline-flex items-center gap-2 px-5 py-2.5 rounded-full liquid-glass text-slate-700 hover:text-indigo-600 text-sm font-bold transition self-start md:self-auto cursor-pointer"
          >
            <Globe className="w-4 h-4 text-indigo-600" /> 查看网页版 PWA 安装教程
          </button>
        </div>

        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {guides.map((g) => (
            <a
              key={g.title}
              href={g.href}
              target="_blank"
              rel="noreferrer"
              className="group p-6 rounded-3xl liquid-glass hover:-translate-y-1 transition-all duration-300 flex flex-col justify-between"
            >
              <div>
                <div className="flex items-center justify-between mb-4">
                  <div className={`w-12 h-12 ${g.color} rounded-2xl flex items-center justify-center group-hover:scale-110 transition-transform`}>
                    {g.icon}
                  </div>
                  <span className="px-2.5 py-0.5 rounded-full bg-slate-100 text-slate-600 text-[11px] font-bold">
                    {g.tag}
                  </span>
                </div>
                <h3 className="text-lg font-black text-slate-900 mb-2 group-hover:text-indigo-600 transition-colors">
                  {g.title}
                </h3>
                <p className="text-sm text-slate-500 leading-relaxed">{g.desc}</p>
              </div>
              <div className="mt-5 pt-4 border-t border-slate-100 flex items-center justify-between text-xs font-bold text-indigo-600">
                <span>打开文档阅读</span>
                <ExternalLink className="w-4 h-4 group-hover:translate-x-0.5 group-hover:-translate-y-0.5 transition-transform" />
              </div>
            </a>
          ))}
        </div>
      </div>
    </section>
  );
};
