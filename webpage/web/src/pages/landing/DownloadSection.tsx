import { useState } from 'react';
import { Monitor, Smartphone, Globe, ChevronRight, ArrowRight, HelpCircle, ExternalLink, Watch, MessageCircle, ChevronDown, ChevronUp, History } from 'lucide-react';
import type { AppInfo } from '../../types';

interface ChangelogEntry {
  version_name: string;
  date: string;
  items: string[];
}

interface DownloadSectionProps {
  androidInfo: AppInfo;
  androidChangelog: ChangelogEntry[];
  windowsLiteInfo: AppInfo;
  windowsLiteChangelog: ChangelogEntry[];
  windowsProInfo: AppInfo;
  windowsProChangelog: ChangelogEntry[];
  webInfo: AppInfo;
  webChangelog: ChangelogEntry[];
  bandInfo: AppInfo;
  bandChangelog: ChangelogEntry[];
  onOpenWeb: () => void;
  onShowInstallGuide: () => void;
}

function getDotColor(item: string): string {
  if (item.startsWith('【新增】')) return 'bg-green-500';
  if (item.startsWith('【优化】')) return 'bg-blue-500';
  if (item.startsWith('【修复】')) return 'bg-orange-500';
  if (item.startsWith('【重构】')) return 'bg-purple-500';
  if (item.startsWith('⚠️')) return 'bg-red-500';
  return 'bg-slate-400';
}

function getDotTextColor(item: string): string {
  if (item.startsWith('【新增】')) return 'text-green-600';
  if (item.startsWith('【优化】')) return 'text-blue-600';
  if (item.startsWith('【修复】')) return 'text-orange-600';
  if (item.startsWith('【重构】')) return 'text-purple-600';
  if (item.startsWith('⚠️')) return 'text-red-600';
  return 'text-slate-500';
}

const BulletItem = ({ item, small = false }: { item: string; small?: boolean }) => (
  <div className={`flex items-start ${small ? 'py-0.5' : 'py-1'}`}>
    <span className={`mt-[5px] shrink-0 w-[6px] h-[6px] rounded-full ${getDotColor(item)}`} />
    <span className={`ml-2.5 leading-relaxed ${small ? 'text-[11px]' : 'text-xs'} ${getDotTextColor(item)}`}>{item}</span>
  </div>
);

const HistoryVersionTile = ({ entry }: { entry: ChangelogEntry }) => {
  const [expanded, setExpanded] = useState(false);

  return (
    <div className="mb-1.5">
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full flex items-center gap-2 px-3.5 py-2.5 bg-slate-100/60 hover:bg-slate-100 rounded-xl transition-colors text-left"
      >
        <span className="text-xs font-semibold text-slate-700 shrink-0">v{entry.version_name}</span>
        {entry.date && <span className="text-[10px] text-slate-400 shrink-0">{entry.date}</span>}
        {!expanded && entry.items.length > 0 && (
          <span className="text-[10px] text-slate-400 truncate">{entry.items[0]}</span>
        )}
        <span className="ml-auto shrink-0">
          {expanded ? <ChevronUp className="w-4 h-4 text-slate-400" /> : <ChevronDown className="w-4 h-4 text-slate-400" />}
        </span>
      </button>
      {expanded && (
        <div className="mt-1 px-3 py-2.5 bg-slate-50/60 rounded-b-xl">
          {entry.items.map((item, i) => (
            <BulletItem key={i} item={item} small />
          ))}
        </div>
      )}
    </div>
  );
};

const ChangelogHistory = ({ changelog, accentColor }: { changelog: ChangelogEntry[]; accentColor: string }) => {
  const [expanded, setExpanded] = useState(false);
  const [visibleCount, setVisibleCount] = useState(5);

  if (!changelog || changelog.length <= 1) return null;

  const history = changelog.slice(1);
  const visibleHistory = history.slice(0, visibleCount);
  const hasMore = history.length > visibleCount;

  return (
    <div className="mt-4">
      <button
        onClick={() => setExpanded(!expanded)}
        className={`flex items-center gap-1.5 text-xs font-bold transition-colors ${accentColor}`}
      >
        <History className="w-3.5 h-3.5" />
        {expanded ? '收起历史日志' : '查看历史日志'}
        {expanded ? <ChevronUp className="w-3.5 h-3.5" /> : <ChevronDown className="w-3.5 h-3.5" />}
      </button>
      {expanded && (
        <div className="mt-3">
          {visibleHistory.map((entry, idx) => (
            <HistoryVersionTile key={idx} entry={entry} />
          ))}
          {hasMore && (
            <button
              onClick={() => setVisibleCount(prev => prev + 5)}
              className="w-full flex items-center justify-center gap-1 py-2 text-xs text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-xl transition-colors"
            >
              <ChevronDown className="w-3.5 h-3.5" />
              还有 {history.length - visibleCount} 个版本，点击加载更多
            </button>
          )}
        </div>
      )}
    </div>
  );
};

export const DownloadSection = ({
  androidInfo,
  androidChangelog,
  windowsLiteInfo,
  windowsLiteChangelog,
  windowsProInfo,
  webInfo,
  webChangelog,
  bandInfo,
  bandChangelog,
  onOpenWeb,
  onShowInstallGuide
}: DownloadSectionProps) => (
  <section id="download" className="py-24 sm:py-48 bg-slate-50 text-center relative overflow-hidden">
    <div className="absolute top-0 left-0 w-full h-px bg-gradient-to-r from-transparent via-slate-200 to-transparent"></div>
    <div className="max-w-[90rem] mx-auto px-4 sm:px-6 lg:px-8">
      <h2 className="text-4xl sm:text-7xl font-black mb-8 text-slate-900 tracking-tighter">准备好开启高效生活了吗？</h2>

      <div className="mb-20">
        <p className="text-slate-500 text-xl font-medium mb-6">全平台支持，数据实时流转，选择适合您的工作方式。</p>

        {/* 备用下载链接徽章 */}
        <div className="inline-flex items-center gap-2 px-4 py-2 bg-blue-50 text-blue-700 rounded-2xl border border-blue-100 shadow-sm hover:bg-blue-100 transition-colors group">
          <ExternalLink className="w-4 h-4 text-blue-500 group-hover:scale-110 transition-transform" />
          <span className="text-sm font-bold">GitHub 下载缓慢？</span>
          <a
            href="https://www.123865.com/s/SCPrVv-8gYi3"
            target="_blank"
            rel="noreferrer"
            className="text-sm font-black underline decoration-2 underline-offset-2 hover:text-blue-900"
          >
            前往备用下载 (123云盘)
          </a>
        </div>
      </div>

      {/* 上排：Flutter 全功能 Pro */}
      <div className="mb-8">
        <div className="inline-flex items-center gap-2 px-3 py-1 bg-purple-50 text-purple-600 rounded-lg text-xs font-bold uppercase tracking-widest mb-6">
          Flutter 全功能 Pro
        </div>
        <div className="max-w-4xl mx-auto">
          <div className="p-8 sm:p-10 bg-white rounded-[3rem] border border-slate-200 shadow-sm hover:shadow-2xl hover:border-purple-500 transition-all group relative overflow-hidden">
            <div className="absolute top-0 right-0 w-40 h-40 bg-purple-500/5 rounded-full blur-3xl group-hover:bg-purple-500/10 transition pointer-events-none"></div>
            <div className="flex flex-col md:flex-row gap-8 items-start relative z-10">
              {/* 左侧：更新日志 */}
              <div className="flex-1 min-w-0 text-left">
                <div className="flex items-center gap-3 mb-4">
                  <div className="w-10 h-10 bg-purple-50 text-purple-600 rounded-xl flex items-center justify-center"><Smartphone className="w-5 h-5" /></div>
                  <div className="w-10 h-10 bg-emerald-50 text-emerald-600 rounded-xl flex items-center justify-center"><Monitor className="w-5 h-5" /></div>
                </div>
                <h3 className="text-xl font-black mb-1 text-slate-900 tracking-tight">Android Pro & Windows Pro</h3>
                <p className="text-sm text-purple-600 font-bold mb-4">v{androidInfo.version || '1.0.0'}</p>
                <div className="text-slate-500 text-sm leading-relaxed whitespace-pre-line text-left">{androidInfo.desc || '全功能 Flutter 体验，跨平台数据无缝同步，AI 智能识别待办，桌面灵动岛实时提醒。'}</div>
                <ChangelogHistory changelog={androidChangelog} accentColor="text-purple-500 hover:text-purple-700" />
              </div>
              {/* 右侧：下载按钮 */}
              <div className="flex flex-col gap-3 shrink-0 w-full sm:w-56">
                {/* Android */}
                <div>
                  <a href={androidInfo.url || "#"} className="flex items-center justify-center gap-2 bg-purple-600 text-white py-3.5 rounded-xl font-bold hover:bg-purple-700 transition shadow-lg shadow-purple-500/20">
                    <Smartphone className="w-5 h-5" /> Android 安装包
                  </a>
                  <p className="text-[11px] text-slate-400 mt-1.5 text-left leading-snug">鸿蒙端可使用卓易通安装，功能可用性自测</p>
                </div>
                {/* Windows + Tai 依赖 合并卡片 */}
                <div className="bg-emerald-50 border border-emerald-200 rounded-xl p-3">
                  <a href={windowsProInfo.url || "#"} className="flex items-center justify-center gap-2 bg-emerald-600 text-white py-3 rounded-lg font-bold hover:bg-emerald-700 transition shadow-md shadow-emerald-500/20">
                    <Monitor className="w-5 h-5" /> Windows 安装包
                  </a>
                  <div className="flex items-center justify-between mt-2 px-1">
                    <span className="text-[11px] text-emerald-700 font-bold">依赖 Tai 核心服务</span>
                    <a href="https://github.com/Planshit/Tai/releases/download/1.5.0.6/Tai1.5.0.6.zip" target="_blank" rel="noreferrer" className="text-[11px] text-emerald-600 font-bold underline hover:text-emerald-900">下载</a>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* 下排：轻量端 & 穿戴 */}
      <div>
        <div className="inline-flex items-center gap-2 px-3 py-1 bg-slate-100 text-slate-500 rounded-lg text-xs font-bold uppercase tracking-widest mb-6">
          轻量端 & 穿戴设备
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 text-left items-stretch">
          {/* Windows Lite */}
          <div className="p-8 sm:p-10 bg-white rounded-[3rem] border border-slate-200 shadow-sm hover:shadow-2xl hover:border-blue-500 transition-all group flex flex-col relative overflow-hidden">
            <div className="absolute top-0 right-0 w-32 h-32 bg-blue-500/5 rounded-full blur-3xl group-hover:bg-blue-500/10 transition pointer-events-none"></div>
            <div className="w-14 h-14 bg-blue-50 text-blue-600 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 group-hover:rotate-3 transition duration-500 shadow-sm"><Monitor className="w-7 h-7" /></div>
            <h3 className="text-2xl font-black mb-3 text-slate-900 tracking-tight">Windows Lite</h3>
            <p className="text-slate-500 text-sm sm:text-base leading-relaxed whitespace-pre-line">
               v{windowsLiteInfo.version || '1.0.0'} <br/>
               {windowsLiteInfo.desc || '原生 C++ 极致轻量，常驻桌面微件，给您最纯净的办公体验。'}
            </p>
            <ChangelogHistory changelog={windowsLiteChangelog} accentColor="text-blue-500 hover:text-blue-700" />
            <div className="space-y-4 mt-4">
               <a href={windowsLiteInfo.url || "#"} className="flex items-center justify-center gap-3 bg-blue-600 text-white w-full py-4 rounded-xl font-black text-lg hover:bg-blue-700 transition shadow-xl shadow-blue-500/30">立即下载 <ChevronRight className="w-6 h-6" /></a>
               <div className="flex items-center justify-between px-5 py-3 bg-blue-50 rounded-xl text-xs text-blue-700 font-bold border border-blue-100">
                  <span>依赖 Tai 核心服务</span>
                  <a href="https://github.com/Planshit/Tai/releases/download/1.5.0.6/Tai1.5.0.6.zip" target="_blank" rel="noreferrer" className="underline hover:text-blue-900">立即前往</a>
               </div>
            </div>
          </div>

          {/* Web */}
          <div className="p-8 sm:p-10 bg-white rounded-[3rem] border border-slate-200 shadow-sm hover:shadow-2xl hover:border-indigo-500 transition-all group flex flex-col relative overflow-hidden">
            <div className="absolute top-0 right-0 w-32 h-32 bg-indigo-500/5 rounded-full blur-3xl group-hover:bg-indigo-500/10 transition pointer-events-none"></div>
            <div className="w-14 h-14 bg-indigo-50 text-indigo-600 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 group-hover:-rotate-3 transition duration-500 shadow-sm"><Globe className="w-7 h-7" /></div>
            <h3 className="text-2xl font-black mb-3 text-slate-900 tracking-tight">Web Station</h3>
            <p className="text-slate-500 text-sm sm:text-base leading-relaxed whitespace-pre-line">
               v{webInfo.version || '1.0.0'} <br/>
               {webInfo.desc || '云端仪表盘，免安装即开即用。深度同步课表与待办，您的跨平台数据中枢。'}
            </p>
            <ChangelogHistory changelog={webChangelog} accentColor="text-indigo-500 hover:text-indigo-700" />
            <div className="space-y-4 mt-4">
              <button onClick={onOpenWeb} className="flex items-center justify-center gap-3 bg-indigo-600 text-white w-full py-4 rounded-xl font-black text-lg hover:bg-indigo-700 transition shadow-xl shadow-indigo-500/30">立即开启 <ArrowRight className="w-6 h-6" /></button>
              <button onClick={onShowInstallGuide} className="flex items-center justify-center gap-2 w-full py-3 rounded-xl font-bold text-sm text-indigo-600 bg-indigo-50 hover:bg-indigo-100 border border-indigo-100 transition">
                <HelpCircle className="w-4 h-4" /> 如何把网页作为 App 安装？
              </button>
            </div>
          </div>

          {/* Xiaomi Band (Vela) */}
          <div className="p-8 sm:p-10 bg-white rounded-[3rem] border border-slate-200 shadow-sm hover:shadow-2xl hover:border-teal-500 transition-all group flex flex-col relative overflow-hidden">
            <div className="absolute top-0 right-0 w-32 h-32 bg-teal-500/5 rounded-full blur-3xl group-hover:bg-teal-500/10 transition pointer-events-none"></div>
            <div className="w-14 h-14 bg-teal-50 text-teal-600 rounded-2xl flex items-center justify-center mb-6 group-hover:scale-110 group-hover:rotate-3 transition duration-500 shadow-sm"><Watch className="w-7 h-7" /></div>
            <h3 className="text-2xl font-black mb-3 text-slate-900 tracking-tight">小米手环 (Vela)</h3>
            <p className="text-slate-500 text-sm sm:text-base leading-relaxed whitespace-pre-line">
               v{bandInfo.version || '1.0.0'} <br/>
               {bandInfo.desc || '抬腕即览待办、倒数日与课程表，蓝牙与手机无缝双向同步，手腕上的效率助手。'}
            </p>
            <ChangelogHistory changelog={bandChangelog} accentColor="text-teal-500 hover:text-teal-700" />
            <div className="space-y-3 mt-4">
              <a href={bandInfo.url || "#"} className="flex items-center justify-center gap-3 bg-teal-600 text-white w-full py-4 rounded-xl font-black text-lg hover:bg-teal-700 transition shadow-xl shadow-teal-500/30">获取快应用 <ChevronRight className="w-6 h-6" /></a>
              <a href="https://www.bandbbs.cn/threads/13984/" target="_blank" rel="noreferrer" className="flex items-center justify-center gap-2 w-full py-3 rounded-xl font-bold text-sm text-teal-600 bg-teal-50 hover:bg-teal-100 border border-teal-100 transition">
                <MessageCircle className="w-4 h-4" /> 常见问题与安装指南
              </a>
              <div className="flex items-start gap-2 px-3 py-2 bg-amber-50 border border-amber-200 rounded-lg mt-2">
                <svg xmlns="http://www.w3.org/2000/svg" className="w-4 h-4 text-amber-600 shrink-0 mt-0.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>
                <p className="text-[11px] text-amber-700 leading-snug">仅基于小米手环 9 Pro 测试，其他设备可能可用但布局错乱</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>
);
