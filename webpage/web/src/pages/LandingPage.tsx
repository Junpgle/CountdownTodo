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
import { DownloadSection } from './landing/DownloadSection';
import { Footer } from './landing/Footer';

export const LandingPage = ({ onOpenWeb }: { onOpenWeb: () => void }) => {
  const [androidInfo, setAndroidInfo] = useState<AppInfo>({ version: '', url: '', desc: '' });
  const [windowsInfo, setWindowsInfo] = useState<AppInfo>({ version: '', url: '', desc: '' });
  const [windowsProInfo, setWindowsProInfo] = useState<AppInfo>({ version: '', url: '', desc: '' });
  const [webInfo, setWebInfo] = useState<AppInfo>({ version: '', url: '', desc: '' });
  const [showInstallGuide, setShowInstallGuide] = useState(false);

  useEffect(() => {
    const fetchManifests = async () => {
      try {
        const [aRes, wRes, webRes] = await Promise.all([
          fetch('https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/update_manifest.json'),
          fetch('https://raw.githubusercontent.com/Junpgle/CountDownTodoLite/refs/heads/master/update_manifest.json'),
          fetch('https://raw.githubusercontent.com/Junpgle/CountdownTodo/refs/heads/master/webpage/web/update_manifest.json')
        ]);
        const [aData, wData, webData] = await Promise.all([aRes.json(), wRes.json(), webRes.json()]);

        setAndroidInfo({
          version: aData.version_name,
          url: aData.update_info.full_package_url,
          desc: aData.update_info.description
        });

        setWindowsProInfo({
          version: aData.version_name,
          url: aData.update_info.PC_package_url,
          desc: aData.update_info.description
        });

        setWindowsInfo({
          version: wData.version_name,
          url: wData.update_info.full_package_url,
          desc: wData.update_info.description
        });

        setWebInfo({
          version: webData.version_name,
          url: '',
          desc: webData.update_info.description
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
          <Hero />
          <Features />
          <WindowsShowcase />
          <AndroidShowcase />
          <WebShowcase onOpenWeb={onOpenWeb} />
          <TimetableShowcase />
          <LiveUpdatesShowcase />
          <WindowsIslandShowcase imageSrc="./island_screenshot.jpg" />
          <BandShowcase />
          <AnalyticsPreview />
          <DownloadSection
            androidInfo={androidInfo}
            windowsInfo={windowsInfo}
            windowsProInfo={windowsProInfo}
            webInfo={webInfo}
            onOpenWeb={onOpenWeb}
            onShowInstallGuide={() => setShowInstallGuide(true)}
          />
          <Footer onOpenWeb={onOpenWeb} />
        </>
      )}
    </div>
  );
};
