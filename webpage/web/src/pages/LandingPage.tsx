import { useState, useEffect, useCallback } from 'react';
import { ArrowLeft, ArrowRight, BookOpen, Download, ExternalLink } from 'lucide-react';
import { WebInstallGuide } from './WebInstallGuide';
import type { AppInfo } from '../types';
import { GUIDE_LINKS, type LandingTabId } from '../constants/links';

import { Navbar } from './landing/Navbar';
import { Hero } from './landing/Hero';
import { Features, AiFeaturesSection } from './landing/Features';
import { OverviewGallery } from './landing/OverviewGallery';
import { GuideLinksSection } from './landing/GuideLinksSection';
import { PlanningCenterShowcase } from './landing/PlanningCenterShowcase';
import { FinanceShowcase } from './landing/FinanceShowcase';
import { WindowsShowcase } from './landing/WindowsShowcase';
import { AndroidShowcase } from './landing/AndroidShowcase';
import { TimetableShowcase } from './landing/TimetableShowcase';
import { LiveUpdatesShowcase } from './landing/LiveUpdatesShowcase';
import { WindowsIslandShowcase } from './landing/WindowsIslandShowcase';
import { BandShowcase } from './landing/BandShowcase';
import { AnalyticsPreview } from './landing/AnalyticsPreview';
import { CollaborationSearchShowcase } from './landing/CollaborationSearchShowcase';
import { PersonalTimelineShowcase } from './landing/PersonalTimelineShowcase';
import { ThirtyDayChallengeShowcase } from './landing/ThirtyDayChallengeShowcase';
import { HabitTrackingShowcase } from './landing/HabitTrackingShowcase';
import { JournalAndDesignShowcase } from './landing/JournalAndDesignShowcase';
import { LANSyncShowcase } from './landing/LANSyncShowcase';
import { DownloadSection } from './landing/DownloadSection';
import { Footer } from './landing/Footer';

interface ChangelogEntry {
  version_name: string;
  date: string;
  items: string[];
}

interface PlatformData {
  info: AppInfo;
  changelog: ChangelogEntry[];
}

interface ProPlatformData extends PlatformData {
  pcUrl?: string;
  androidArchUrls?: {
    'arm64-v8a'?: string;
    'armeabi-v7a'?: string;
    x86_64?: string;
  };
  macArm64Url?: string;
  macX64Url?: string;
}

const TAB_ORDER: Array<{ id: LandingTabId; label: string; subtitle: string }> = [
  { id: 'overview', label: '首页总览', subtitle: '核心特性与全平台下载' },
  { id: 'ai', label: 'AI 助手 2.0', subtitle: '每日建议 · 语音速记 · 识图 · MCP' },
  { id: 'planning', label: '规划与协作', subtitle: '时间块 · 课表调休 · 团队甘特图 · 全局搜索' },
  { id: 'finance-growth', label: '记账与成长', subtitle: '智能账本 · 四维习惯 · 挑战 · 日记与美学' },
  { id: 'sync-platforms', label: '多端与同步', subtitle: 'ECDH 局域网互传 · 双端灵动岛 · 手环' },
];

function parseTabFromHash(hash: string): LandingTabId {
  const clean = hash.replace(/^#/, '');
  if (clean === 'ai' || clean === 'ai-features') return 'ai';
  if (clean === 'planning' || clean === 'timetable' || clean === 'collaboration-search') {
    return 'planning';
  }
  if (
    clean === 'finance-growth' ||
    clean === 'finance' ||
    clean === 'habit-tracking' ||
    clean === 'thirty-day-challenge' ||
    clean === 'journal-design' ||
    clean === 'timeline'
  ) {
    return 'finance-growth';
  }
  if (
    clean === 'sync-platforms' ||
    clean === 'lan-sync' ||
    clean === 'windows-island' ||
    clean === 'desktop' ||
    clean === 'mobile' ||
    clean === 'band'
  ) {
    return 'sync-platforms';
  }
  return 'overview';
}

export const LandingPage = () => {
  const [activeTab, setActiveTab] = useState<LandingTabId>(() =>
    typeof window !== 'undefined' ? parseTabFromHash(window.location.hash) : 'overview',
  );
  const [proData, setProData] = useState<ProPlatformData>({
    info: { version: '', url: '', desc: '' },
    changelog: [],
  });
  const [windowsLiteData, setWindowsLiteData] = useState<PlatformData>({
    info: { version: '', url: '', desc: '' },
    changelog: [],
  });
  const [bandData, setBandData] = useState<PlatformData>({
    info: { version: '', url: '', desc: '' },
    changelog: [],
  });
  const [showInstallGuide, setShowInstallGuide] = useState(false);

  const selectTab = useCallback((tab: LandingTabId, anchorId?: string) => {
    setActiveTab(tab);
    const targetHash = anchorId ? `#${anchorId}` : `#${tab}`;
    if (window.location.hash !== targetHash) {
      window.history.pushState(null, '', targetHash);
    }
    if (anchorId) {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          const el = document.getElementById(anchorId);
          if (el) {
            el.scrollIntoView({ behavior: 'smooth' });
          } else {
            window.scrollTo({ top: 0, behavior: 'smooth' });
          }
        });
      });
    } else {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }
  }, []);

  useEffect(() => {
    const onHashChange = () => {
      setActiveTab(parseTabFromHash(window.location.hash));
    };
    window.addEventListener('hashchange', onHashChange);
    return () => window.removeEventListener('hashchange', onHashChange);
  }, []);

  useEffect(() => {
    const fetchManifests = async () => {
      try {
        const [aRes, wRes, bandRes] = await Promise.all([
          fetch('https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json'),
          fetch('https://raw.githubusercontent.com/Junpgle/CountDownTodoLite/refs/heads/master/update_manifest.json'),
          fetch('https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/CountDownTodo-band/update_manifest.json'),
        ]);
        const [aData, wData, bData] = await Promise.all([aRes.json(), wRes.json(), bandRes.json()]);

        const updateInfo = aData.update_info || {};
        setProData({
          info: {
            version: aData.version_name,
            url: updateInfo.full_package_url || '',
            desc: updateInfo.description || '',
          },
          pcUrl: updateInfo.PC_package_url || '',
          androidArchUrls: {
            'arm64-v8a': updateInfo.android_arch_packages?.['arm64-v8a'] || updateInfo.full_package_url || '',
            'armeabi-v7a': updateInfo.android_arch_packages?.['armeabi-v7a'] || '',
            x86_64: updateInfo.android_arch_packages?.x86_64 || '',
          },
          macArm64Url: updateInfo.mac_arch_packages?.arm64 || updateInfo.mac_package_url || '',
          macX64Url: updateInfo.mac_arch_packages?.x86_64 || '',
          changelog: aData.changelog_history || [],
        });

        setWindowsLiteData({
          info: {
            version: wData.version_name,
            url: wData.update_info?.full_package_url || '',
            desc: wData.update_info?.description || '',
          },
          changelog: wData.changelog_history || [],
        });

        setBandData({
          info: {
            version: bData.version_name,
            url: bData.update_info?.full_package_url || '',
            desc: bData.update_info?.description || '',
          },
          changelog: bData.changelog_history || [],
        });
      } catch (e) {
        console.error('Manifest JSON 解析拉取错误:', e);
      }
    };
    fetchManifests();
  }, []);

  const currentTabIndex = TAB_ORDER.findIndex((t) => t.id === activeTab);
  const prevTab = currentTabIndex > 0 ? TAB_ORDER[currentTabIndex - 1] : null;
  const nextTab =
    currentTabIndex >= 0 && currentTabIndex < TAB_ORDER.length - 1
      ? TAB_ORDER[currentTabIndex + 1]
      : null;

  return (
    <div className="bg-white min-h-screen">
      {showInstallGuide && <WebInstallGuide onBack={() => setShowInstallGuide(false)} />}
      {!showInstallGuide && (
        <>
          <Navbar activeTab={activeTab} onSelectTab={selectTab} />

          {activeTab === 'overview' && (
            <>
              <Hero
                version={proData.info.version}
                date={proData.changelog[0]?.date}
              />
              <OverviewGallery onSelectTab={(tab, anchorId) => selectTab(tab, anchorId)} />
              <Features onSelectTab={(tab, anchorId) => selectTab(tab, anchorId)} />
              <GuideLinksSection onShowInstallGuide={() => setShowInstallGuide(true)} />
              <DownloadSection
                androidInfo={proData.info}
                androidChangelog={proData.changelog}
                androidArchUrls={proData.androidArchUrls}
                windowsLiteInfo={windowsLiteData.info}
                windowsLiteChangelog={windowsLiteData.changelog}
                windowsProInfo={{ ...proData.info, url: proData.pcUrl || '' }}
                windowsProChangelog={proData.changelog}
                macInfo={{ ...proData.info, url: proData.macArm64Url || '' }}
                macArchUrls={{ arm64: proData.macArm64Url, x86_64: proData.macX64Url }}
                bandInfo={bandData.info}
                bandChangelog={bandData.changelog}
                onShowInstallGuide={() => setShowInstallGuide(true)}
              />
            </>
          )}

          {activeTab !== 'overview' && (
            <div className="pt-16 sm:pt-20" />
          )}

          {activeTab === 'ai' && <AiFeaturesSection />}

          {activeTab === 'planning' && (
            <>
              <PlanningCenterShowcase />
              <TimetableShowcase />
              <CollaborationSearchShowcase />
            </>
          )}

          {activeTab === 'finance-growth' && (
            <>
              <FinanceShowcase />
              <HabitTrackingShowcase />
              <ThirtyDayChallengeShowcase />
              <JournalAndDesignShowcase />
              <PersonalTimelineShowcase />
            </>
          )}

          {activeTab === 'sync-platforms' && (
            <>
              <div className="bg-white border-b border-slate-100">
                <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-5 flex flex-wrap items-center justify-center gap-3">
                  <a
                    href={GUIDE_LINKS.widgetFeatures}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-indigo-50 text-indigo-700 hover:bg-indigo-100 text-xs sm:text-sm font-bold transition"
                  >
                    <BookOpen className="w-4 h-4" /> 桌面小部件高阶教程 <ExternalLink className="w-3.5 h-3.5" />
                  </a>
                  <a
                    href={GUIDE_LINKS.bandGuide}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-teal-50 text-teal-700 hover:bg-teal-100 text-xs sm:text-sm font-bold transition"
                  >
                    <BookOpen className="w-4 h-4" /> 小米手环快应用安装指南 <ExternalLink className="w-3.5 h-3.5" />
                  </a>
                </div>
              </div>
              <LANSyncShowcase />
              <WindowsIslandShowcase imageSrc="./island_screenshot.webp" />
              <WindowsShowcase />
              <AndroidShowcase />
              <LiveUpdatesShowcase />
              <BandShowcase />
              <AnalyticsPreview />
            </>
          )}

          {activeTab !== 'overview' && (
            <section className="py-12 bg-slate-50 border-t border-slate-200">
              <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex flex-col sm:flex-row items-center justify-between gap-4">
                <div className="flex flex-wrap items-center gap-3">
                  {prevTab && (
                    <button
                      type="button"
                      onClick={() => selectTab(prevTab.id)}
                      className="inline-flex items-center gap-2 px-5 py-3 rounded-2xl bg-white border border-slate-200 text-slate-700 hover:border-indigo-300 hover:text-indigo-600 font-bold text-sm shadow-sm transition cursor-pointer"
                    >
                      <ArrowLeft className="w-4 h-4" /> {prevTab.label}
                    </button>
                  )}
                  {nextTab && (
                    <button
                      type="button"
                      onClick={() => selectTab(nextTab.id)}
                      className="inline-flex items-center gap-2 px-5 py-3 rounded-2xl bg-white border border-slate-200 text-slate-700 hover:border-indigo-300 hover:text-indigo-600 font-bold text-sm shadow-sm transition cursor-pointer"
                    >
                      下一专题：{nextTab.label} <ArrowRight className="w-4 h-4" />
                    </button>
                  )}
                </div>
                <button
                  type="button"
                  onClick={() => selectTab('overview', 'download')}
                  className="inline-flex items-center gap-2 px-7 py-3.5 rounded-full bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-sm shadow-lg shadow-indigo-500/25 transition cursor-pointer"
                >
                  <Download className="w-4 h-4" /> 前往下载全平台客户端
                </button>
              </div>
            </section>
          )}

          <Footer onSelectTab={selectTab} />
        </>
      )}
    </div>
  );
};
