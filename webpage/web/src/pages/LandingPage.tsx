import { useState, useEffect } from 'react';
import { WebInstallGuide } from './WebInstallGuide';
import type { AppInfo } from '../types';

import { Navbar } from './landing/Navbar';
import { Hero } from './landing/Hero';
import { Features } from './landing/Features';
import { WindowsShowcase } from './landing/WindowsShowcase';
import { AndroidShowcase } from './landing/AndroidShowcase';
import { WebShowcase } from './landing/WebShowcase';
import { TimetableShowcase } from './landing/TimetableShowcase';
import { LiveUpdatesShowcase } from './landing/LiveUpdatesShowcase';
import { WindowsIslandShowcase } from './landing/WindowsIslandShowcase';
import { BandShowcase } from './landing/BandShowcase';
import { AnalyticsPreview } from './landing/AnalyticsPreview';
import { CollaborationSearchShowcase } from './landing/CollaborationSearchShowcase';
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

export const LandingPage = ({ onOpenWeb }: { onOpenWeb: () => void }) => {
  const [androidData, setAndroidData] = useState<PlatformData>({ info: { version: '', url: '', desc: '' }, changelog: [] });
  const [windowsLiteData, setWindowsLiteData] = useState<PlatformData>({ info: { version: '', url: '', desc: '' }, changelog: [] });
  const [webData, setWebData] = useState<PlatformData>({ info: { version: '', url: '', desc: '' }, changelog: [] });
  const [bandData, setBandData] = useState<PlatformData>({ info: { version: '', url: '', desc: '' }, changelog: [] });
  const [showInstallGuide, setShowInstallGuide] = useState(false);

  useEffect(() => {
    const fetchManifests = async () => {
      try {
        const [aRes, wRes, webRes, bandRes] = await Promise.all([
          fetch('https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json'),
          fetch('https://raw.githubusercontent.com/Junpgle/CountDownTodoLite/refs/heads/master/update_manifest.json'),
          fetch('https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/webpage/web/update_manifest.json'),
          fetch('https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/CountDownTodo-band/update_manifest.json')
        ]);
        const [aData, wData, webData, bandData] = await Promise.all([aRes.json(), wRes.json(), webRes.json(), bandRes.json()]);

        setAndroidData({
          info: {
            version: aData.version_name,
            url: aData.update_info.full_package_url,
            desc: aData.update_info.description
          },
          changelog: aData.changelog_history || []
        });

        setWindowsLiteData({
          info: {
            version: wData.version_name,
            url: wData.update_info.full_package_url,
            desc: wData.update_info.description
          },
          changelog: wData.changelog_history || []
        });

        setWebData({
          info: {
            version: webData.version_name,
            url: '',
            desc: webData.update_info.description
          },
          changelog: webData.changelog_history || []
        });

        setBandData({
          info: {
            version: bandData.version_name,
            url: bandData.update_info.full_package_url,
            desc: bandData.update_info.description
          },
          changelog: bandData.changelog_history || []
        });

      } catch (e) {
        console.error("Manifest JSON 解析拉取错误:", e);
      }
    };
    fetchManifests();
  }, []);

  return (
    <div className="bg-white min-h-screen">
      {showInstallGuide && <WebInstallGuide onBack={() => setShowInstallGuide(false)} />}
      {!showInstallGuide && (
        <>
          <Navbar />
          <Hero 
            version={androidData.info.version} 
            date={androidData.changelog[0]?.date} 
          />
          <Features />
          <CollaborationSearchShowcase />
          <LANSyncShowcase />
          <WindowsShowcase />
          <AndroidShowcase />
          <WebShowcase onOpenWeb={onOpenWeb} />
          <TimetableShowcase />
          <LiveUpdatesShowcase />
          <WindowsIslandShowcase imageSrc="./island_screenshot.webp" />
          <BandShowcase />
          <AnalyticsPreview />
          <DownloadSection
            androidInfo={androidData.info}
            androidChangelog={androidData.changelog}
            windowsLiteInfo={windowsLiteData.info}
            windowsLiteChangelog={windowsLiteData.changelog}
            windowsProInfo={androidData.info}
            windowsProChangelog={androidData.changelog}
            webInfo={webData.info}
            webChangelog={webData.changelog}
            bandInfo={bandData.info}
            bandChangelog={bandData.changelog}
            onOpenWeb={onOpenWeb}
            onShowInstallGuide={() => setShowInstallGuide(true)}
          />
          <Footer onOpenWeb={onOpenWeb} />
        </>
      )}
    </div>
  );
};
