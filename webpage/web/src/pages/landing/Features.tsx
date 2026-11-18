import {
  Monitor,
  Smartphone,
  CloudLightning,
  Brain,
  MessageSquare,
  BellRing,
  Users,
  Wifi,
  CheckSquare,
  Sparkles,
  Wallet,
  CalendarRange,
  BookHeart,
  CalendarDays,
  Cpu,
  Mic,
  Plug,
  ArrowRight,
  ExternalLink,
  BookOpen,
} from 'lucide-react';
import { ShowcaseImageSlot } from '../../components/ShowcaseImageSlot';
import { GUIDE_LINKS, type LandingTabId } from '../../constants/links';

export const Features = ({
  onSelectTab,
}: {
  onSelectTab?: (tab: LandingTabId, anchorId?: string) => void;
}) => {
  const features: Array<{
    title: string;
    desc: string;
    icon: React.ReactNode;
    color: string;
    tab: LandingTabId;
    anchorId: string;
    tabLabel: string;
  }> = [
    {
      title: '桌面端与双端灵动岛',
      desc: '支持 Windows 原生 C++ 轻量版、Flutter Pro 与 macOS（Apple Silicon & Intel）；macOS 灵动岛支持拖放文件/文本 AI 识待办与 QuickLook 预览。',
      icon: <Monitor className="w-6 h-6" />,
      color: 'bg-blue-50 text-blue-600',
      tab: 'sync-platforms',
      anchorId: 'windows-island',
      tabLabel: '多端与同步 · 双端灵动岛',
    },
    {
      title: '移动与平板自适应',
      desc: '手机与平板深度自适应分屏，支持 Material 3 动态壁纸取色、纯黑 OLED 省电模式，以及平板近期账单与待办地点桌面小组件。',
      icon: <Smartphone className="w-6 h-6" />,
      color: 'bg-purple-50 text-purple-600',
      tab: 'sync-platforms',
      anchorId: 'mobile',
      tabLabel: '多端与同步 · 移动与平板',
    },
    {
      title: 'AI 智能助手 2.0',
      desc: '首页每日 AI 智能建议卡片、长期记忆偏好、位置/设备上下文查询、长按底部 + 语音速记、流式识图与单轮工具预算控制。',
      icon: <Brain className="w-6 h-6" />,
      color: 'bg-emerald-50 text-emerald-600',
      tab: 'ai',
      anchorId: 'ai-features',
      tabLabel: 'AI 助手 2.0',
    },
    {
      title: '个人记账与 AI 账本',
      desc: '支持微信（CSV/XLSX）与支付宝（CSV）账单批量导入、账户互转、预算看板、交互式支出环形图、账单日历与截图自动入账草案。',
      icon: <Wallet className="w-6 h-6" />,
      color: 'bg-teal-50 text-teal-600',
      tab: 'finance-growth',
      anchorId: 'finance',
      tabLabel: '记账与成长 · 个人记账',
    },
    {
      title: '规划中心与时间块',
      desc: '待办拖拽排入时间轴并按小时动态分轨，大任务一键拆分，自动扣减课表、固定日程与习惯软预留，支持执行复盘与漏做恢复。',
      icon: <CalendarRange className="w-6 h-6" />,
      color: 'bg-indigo-50 text-indigo-600',
      tab: 'planning',
      anchorId: 'planning',
      tabLabel: '规划与协作 · 规划中心',
    },
    {
      title: '智能课表与固定日程',
      desc: '高校教务一键导入、节假日放假与调休补课平移、固定日程与待办双向关联及准备时间预留，周视图重叠日程 +N 折叠弹窗。',
      icon: <CalendarDays className="w-6 h-6" />,
      color: 'bg-sky-50 text-sky-600',
      tab: 'planning',
      anchorId: 'timetable',
      tabLabel: '规划与协作 · 智能课表',
    },
    {
      title: '四维习惯与专属日历',
      desc: '涵盖完成、时长、数量、时间点四维打卡，支持防误触延迟落章与按单个习惯筛选专属完成日历，深度联动番茄钟与规划容量。',
      icon: <CheckSquare className="w-6 h-6" />,
      color: 'bg-cyan-50 text-cyan-600',
      tab: 'finance-growth',
      anchorId: 'habit-tracking',
      tabLabel: '记账与成长 · 习惯养成',
    },
    {
      title: '30 天生活实验',
      desc: '每天随机抽取一件新鲜小事，写下当下感受并配图记录，挑战结束后一键生成专属纪念长图海报分享给好友。',
      icon: <Sparkles className="w-6 h-6" />,
      color: 'bg-orange-50 text-orange-600',
      tab: 'finance-growth',
      anchorId: 'thirty-day-challenge',
      tabLabel: '记账与成长 · 30天挑战',
    },
    {
      title: '私密日记、Liquid Glass 与勋章',
      desc: '图文日记与独立防误删回收站；可调透光度/模糊度的 Liquid Glass 液态玻璃与 60 FPS 负载压力监控，以及数十枚成就勋章。',
      icon: <BookHeart className="w-6 h-6" />,
      color: 'bg-rose-50 text-rose-600',
      tab: 'finance-growth',
      anchorId: 'journal-design',
      tabLabel: '记账与成长 · 日记与美学',
    },
    {
      title: '多端云同步与健康诊断',
      desc: 'Batch 批量与 Delta 增量合并，冲突收件箱可视化比对合并；内置同步健康度水位诊断、重复待办合并去重与定期自动快照备份。',
      icon: <CloudLightning className="w-6 h-6" />,
      color: 'bg-amber-50 text-amber-600',
      tab: 'sync-platforms',
      anchorId: 'analytics',
      tabLabel: '多端与同步 · 数据聚合',
    },
    {
      title: '局域网 ECDH 面对面互传',
      desc: '同一 Wi-Fi/热点下零流量点对点直连，采用 ECDH + AES-GCM 端到端加密、面对面扫码配对、隐私域独立控制与低电量策略联动。',
      icon: <Wifi className="w-6 h-6" />,
      color: 'bg-lime-50 text-lime-600',
      tab: 'sync-platforms',
      anchorId: 'lan-sync',
      tabLabel: '多端与同步 · 局域网同步',
    },
    {
      title: '全局搜索与团队协作',
      desc: '自然语言日期搜遍待办、账单、日记与设置项；群组团队支持「共同完成/各自独立打卡」与全景甘特图、成员活跃热力图。',
      icon: <Users className="w-6 h-6" />,
      color: 'bg-fuchsia-50 text-fuchsia-600',
      tab: 'planning',
      anchorId: 'collaboration-search',
      tabLabel: '规划与协作 · 协作与搜索',
    },
  ];

  return (
    <section id="features" className="cv-auto py-16 sm:py-24 bg-white">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="text-center mb-14">
          <h2 className="text-3xl sm:text-5xl font-black text-slate-900 mb-4 tracking-tight">核心特性全景</h2>
          <p className="text-lg text-slate-500 max-w-2xl mx-auto">
            按模块分栏深入探索——点击任意特性卡片即可直达对应专题板块
          </p>
        </div>
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-7">
          {features.map((f, i) => (
            <button
              key={i}
              type="button"
              onClick={() => onSelectTab?.(f.tab, f.anchorId)}
              className="text-left p-8 rounded-[2.25rem] bg-slate-50 hover:bg-white hover:shadow-xl transition-all duration-500 group border border-slate-100 hover:border-indigo-200 flex flex-col justify-between cursor-pointer"
            >
              <div>
                <div className={`w-13 h-13 ${f.color} rounded-2xl flex items-center justify-center mb-5 group-hover:scale-110 transition`}>
                  {f.icon}
                </div>
                <h3 className="text-xl font-black mb-3 text-slate-900 group-hover:text-indigo-600 transition-colors">
                  {f.title}
                </h3>
                <p className="text-slate-500 leading-relaxed text-sm sm:text-base">{f.desc}</p>
              </div>
              <div className="mt-5 pt-4 border-t border-slate-200/60 flex items-center justify-between text-xs font-bold text-indigo-600 opacity-80 group-hover:opacity-100">
                <span>进入「{f.tabLabel}」详介</span>
                <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
              </div>
            </button>
          ))}
        </div>
      </div>
    </section>
  );
};

export const AiFeaturesSection = () => (
  <section id="ai-features" className="py-16 sm:py-24 bg-gradient-to-b from-slate-50 to-white">
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div className="text-center mb-16 sm:mb-20">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-indigo-100 text-indigo-700 rounded-full text-sm font-bold mb-4">
          <Sparkles className="w-4 h-4" /> AI 智能助手 2.0
        </div>
        <h2 className="text-3xl sm:text-5xl font-black text-slate-900 mb-4 tracking-tight">主动洞察，更懂你的工作流</h2>
        <p className="text-lg text-slate-500 max-w-2xl mx-auto mb-8">
          不仅能听懂一句话、看懂一张图，还能记住偏好、分析空档并直连外部 AI 客户端
        </p>
        <a
          href={GUIDE_LINKS.aiAssistantAdvanced}
          target="_blank"
          rel="noreferrer"
          className="inline-flex items-center gap-2 px-6 py-3 rounded-full bg-indigo-600 hover:bg-indigo-700 text-white text-sm font-bold shadow-lg shadow-indigo-500/20 transition"
        >
          <BookOpen className="w-4 h-4" /> 阅读 AI 助手高阶使用指南 <ExternalLink className="w-4 h-4" />
        </a>
      </div>

      {/* 1. 每日 AI 智能建议、长期记忆偏好与工具预算 (v7.24 新增) */}
      <div className="flex flex-col md:flex-row-reverse gap-12 items-center mb-20">
        <div className="flex-1">
          <div className="flex items-center gap-3 mb-5">
            <div className="w-13 h-13 bg-indigo-50 text-indigo-600 rounded-2xl flex items-center justify-center">
              <Sparkles className="w-6 h-6" />
            </div>
            <span className="px-3 py-1 rounded-full bg-indigo-100 text-indigo-700 text-xs font-black">v7.24 新增</span>
          </div>
          <h3 className="text-2xl sm:text-3xl font-black mb-4 text-slate-900">每日 AI 智能建议、记忆偏好与上下文感知</h3>
          <p className="text-slate-500 leading-relaxed text-base mb-4">
            首页「今日 AI 建议」水波纹卡片结合你的课表空档、待办优先级、习惯进度与消费节奏，主动生成今日行动简报。
          </p>
          <p className="text-slate-500 leading-relaxed text-base">
            支持开启 AI 长期记忆偏好、查询当前位置与设备上下文（电量/网络），可在对话内自定义单轮工具调用预算，并在折叠态实时查看思考动作摘要。
          </p>
        </div>
        <div className="flex-1 w-full">
          <div className="grid grid-cols-1 sm:grid-cols-12 gap-5 items-center">
            <div className="sm:col-span-7">
              <div className="rounded-3xl overflow-hidden border border-slate-200 shadow-xl bg-white">
                <ShowcaseImageSlot
                  src="./ai_daily_suggestion.jpg"
                  alt="每日 AI 智能建议卡片与记忆工具调用预览"
                  fileNameHint="ai_daily_suggestion.jpg"
                  imgClassName="w-full h-auto object-cover"
                  fallback={
                    <div className="p-6 sm:p-7 bg-gradient-to-br from-indigo-950 via-slate-900 to-violet-950 text-white text-left">
                      <div className="text-sm font-bold">今日 AI 建议预览</div>
                    </div>
                  }
                />
              </div>
            </div>
            <div className="sm:col-span-5 flex justify-center">
              <div className="w-full max-w-[235px] rounded-3xl overflow-hidden border border-slate-200 shadow-xl bg-white p-1.5 hover:shadow-2xl transition-all duration-500">
                <img
                  src="./ai_chat_tool_use.jpg"
                  alt="AI 思考过程摘要与账单工具调用查询"
                  loading="lazy"
                  className="w-full h-auto rounded-[1.25rem] object-contain"
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* 2. AI 多模态流式识别与长按语音速记 */}
      <div className="flex flex-col md:flex-row gap-12 items-center mb-20">
        <div className="flex-1">
          <div className="flex items-center gap-3 mb-5">
            <div className="w-13 h-13 bg-emerald-50 text-emerald-600 rounded-2xl flex items-center justify-center">
              <Brain className="w-6 h-6" />
            </div>
            <div className="w-10 h-10 bg-amber-50 text-amber-600 rounded-xl flex items-center justify-center">
              <Mic className="w-5 h-5" />
            </div>
          </div>
          <h3 className="text-2xl sm:text-3xl font-black mb-4 text-slate-900">多模态流式识图 &amp; 长按「+」语音速记</h3>
          <p className="text-slate-500 leading-relaxed text-base mb-4">
            不用打字！长按首页底部带流光边框的「+」按钮即可直接说话速记，松手自动转文字生成待办或记账草案。
          </p>
          <p className="text-slate-500 leading-relaxed text-base">
            从相册/微信分享群通知、订单或付款截图给 App，支持<strong>流式过程预览与原始输出查看</strong>；同一张图既有付款金额又有取餐码时，自动拆分为待办提醒与记账草案，绝不误把取餐码当成金额。
          </p>
        </div>
        <div className="flex-1 w-full">
          <div className="grid grid-cols-1 sm:grid-cols-12 gap-5 items-center">
            <div className="sm:col-span-5 flex justify-center">
              <div className="w-full max-w-[240px] rounded-3xl overflow-hidden border border-slate-200 shadow-xl bg-white p-1.5 hover:shadow-2xl transition-all duration-500">
                <img
                  src="./ai_voice_quick_add.jpg"
                  alt="长按底部加号语音速记"
                  loading="lazy"
                  className="w-full h-auto rounded-[1.25rem] object-contain"
                />
              </div>
            </div>
            <div className="sm:col-span-7">
              <div className="rounded-2xl overflow-hidden border border-slate-200 shadow-lg bg-slate-100 aspect-[16/9] flex items-center justify-center group hover:shadow-xl transition-all duration-500">
                <img
                  src="./ai_todo.webp"
                  alt="AI 识别过程"
                  loading="lazy"
                  className="w-full h-full object-cover"
                  onError={(e) => {
                    (e.target as HTMLImageElement).style.display = 'none';
                    const parent = (e.target as HTMLImageElement).parentElement;
                    if (parent) {
                      const fallback = document.createElement('div');
                      fallback.className = 'flex flex-col items-center gap-3 text-slate-400';
                      fallback.innerHTML = `<span class="text-sm font-medium">截图展示区</span><span class="text-xs">替换 ai_todo.webp</span>`;
                      parent.appendChild(fallback);
                    }
                  }}
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* 3. 特殊待办上岛 & macOS 灵动岛拖放 */}
      <div className="flex flex-col md:flex-row-reverse gap-12 items-center mb-20">
        <div className="flex-1">
          <div className="w-13 h-13 bg-rose-50 text-rose-600 rounded-2xl flex items-center justify-center mb-5">
            <BellRing className="w-6 h-6" />
          </div>
          <h3 className="text-2xl sm:text-3xl font-black mb-4 text-slate-900">特殊待办上岛 &amp; macOS 拖放识待办</h3>
          <p className="text-slate-500 leading-relaxed text-base mb-4">
            识别到外卖取餐、快递取件等特殊待办后，自动提取核心号码推送到灵动岛与实时通知栏，走到驿站抬手即看。
          </p>
          <p className="text-slate-500 leading-relaxed text-base">
            在 macOS 端，只需把截图文件或一段聊天文字直接<strong>拖放至桌面灵动岛</strong>，即刻触发 AI 解析创建待办并联动 QuickLook 快速预览。
          </p>
        </div>
        <div className="flex-1 w-full">
          <div className="rounded-2xl overflow-hidden border border-slate-200 shadow-lg bg-slate-100 aspect-[16/9] flex items-center justify-center group hover:shadow-xl transition-all duration-500">
            <img
              src="./ai_todo_special.webp"
              alt="特殊待办上岛"
              loading="lazy"
              className="w-full h-full object-cover"
              onError={(e) => {
                (e.target as HTMLImageElement).style.display = 'none';
                const parent = (e.target as HTMLImageElement).parentElement;
                if (parent) {
                  const fallback = document.createElement('div');
                  fallback.className = 'flex flex-col items-center gap-3 text-slate-400';
                  fallback.innerHTML = `<span class="text-sm font-medium">截图展示区</span><span class="text-xs">替换 ai_todo_special.webp</span>`;
                  parent.appendChild(fallback);
                }
              }}
            />
          </div>
        </div>
      </div>

      {/* 4. 多模型配置、MCP 协议与 Token 成本账本 */}
      <div className="flex flex-col md:flex-row gap-12 items-center">
        <div className="flex-1">
          <div className="flex items-center gap-3 mb-5">
            <div className="w-13 h-13 bg-cyan-50 text-cyan-600 rounded-2xl flex items-center justify-center">
              <MessageSquare className="w-6 h-6" />
            </div>
            <div className="w-10 h-10 bg-purple-50 text-purple-600 rounded-xl flex items-center justify-center">
              <Plug className="w-5 h-5" />
            </div>
            <div className="w-10 h-10 bg-amber-50 text-amber-600 rounded-xl flex items-center justify-center">
              <Cpu className="w-5 h-5" />
            </div>
          </div>
          <h3 className="text-2xl sm:text-3xl font-black mb-4 text-slate-900">多模型切换、MCP 协议接入 &amp; Token 成本账本</h3>
          <p className="text-slate-500 leading-relaxed text-base mb-4">
            内置智谱 GLM、DeepSeek、MiMo 等模型预设，文本模型与视觉模型独立配置，支持任意 OpenAI 兼容 Base URL；API 密钥存入系统安全存储，不配置 Key 也可复制提示词配合外部 AI 使用。
          </p>
          <p className="text-slate-500 leading-relaxed text-base">
            支持通过 <strong>MCP（Model Context Protocol）</strong>将 Claude Desktop、Cursor 等客户端直连你的课表与待办；内置 AI Token 用量与费用统计，可按百万 Token 单价自动同步至个人账本。
          </p>
        </div>
        <div className="flex-1 w-full">
          <div className="grid grid-cols-2 gap-5 items-center justify-items-center">
            <div className="rounded-3xl overflow-hidden border border-slate-200 shadow-lg bg-white p-1.5 flex items-center justify-center hover:shadow-xl transition-all duration-500">
              <img
                src="./ai_model_config.webp"
                alt="大模型配置界面"
                loading="lazy"
                className="max-h-[480px] w-auto rounded-[1.25rem] object-contain"
                onError={(e) => {
                  (e.target as HTMLImageElement).style.display = 'none';
                  const parent = (e.target as HTMLImageElement).parentElement;
                  if (parent) {
                    const fallback = document.createElement('div');
                    fallback.className = 'flex flex-col items-center gap-3 text-slate-400 py-16';
                    fallback.innerHTML = `<span class="text-sm font-medium">截图展示区</span><span class="text-xs">替换 ai_model_config.webp</span>`;
                    parent.appendChild(fallback);
                  }
                }}
              />
            </div>
            <div className="rounded-3xl overflow-hidden border border-slate-200 shadow-lg bg-white p-1.5 flex items-center justify-center hover:shadow-xl transition-all duration-500">
              <img
                src="./ai_usage_cost.jpg"
                alt="AI 调用费用统计与自动写入记账"
                loading="lazy"
                className="max-h-[480px] w-auto rounded-[1.25rem] object-contain"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>
);
