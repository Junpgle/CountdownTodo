import {
  Wifi,
  FileUp,
  Zap,
  Smartphone,
  Monitor,
  ArrowLeftRight,
  Lock,
  QrCode,
  BatteryCharging,
  ShieldCheck,
} from 'lucide-react';
import { MonitorFrame } from '../../components/Frames';

export const LANSyncShowcase = () => {
  return (
    <section id="lan-sync" className="cv-auto py-24 sm:py-36 bg-slate-50 relative overflow-hidden">
      <div className="absolute top-0 left-0 w-full h-full opacity-[0.02] pointer-events-none" style={{ backgroundImage: 'radial-gradient(#6366f1 1px, transparent 1px)', backgroundSize: '40px 40px' }}></div>
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center relative z-10">
        <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-indigo-100 text-indigo-700 rounded-full text-sm font-bold mb-6">
          <Wifi className="w-5 h-5" /> v7.24 升级 · 局域网面对面加密同步 2.0
        </div>
        <h2 className="text-4xl sm:text-5xl lg:text-6xl font-black mb-6 text-slate-900 tracking-tight">
          断网也能极速互传，<br />端到端加密零泄漏
        </h2>
        <p className="text-slate-500 text-lg sm:text-xl max-w-3xl mx-auto leading-relaxed mb-16 px-4">
          只要在同一 Wi-Fi 或手机热点下（离线模式也可按需手动探测），无需服务器中转。v7.24 全新引入 <strong>ECDH + AES-GCM 端到端加密</strong>、<strong>面对面扫码配对</strong>、<strong>隐私域独立配置</strong> 与 <strong>macOS 低电量省电策略联动</strong>。
        </p>

        <div className="relative max-w-6xl mx-auto mb-20">
          <div className="grid md:grid-cols-3 gap-7 relative z-20 text-left">
            <div className="bg-white p-8 rounded-[2.25rem] shadow-xl border border-slate-100 flex flex-col group hover:-translate-y-2 transition-all duration-500">
              <div className="w-16 h-16 bg-indigo-50 text-indigo-600 rounded-2xl flex items-center justify-center mb-5 group-hover:scale-110 transition duration-500">
                <Lock className="w-8 h-8" />
              </div>
              <h3 className="text-xl font-black text-slate-900 mb-3">ECDH + AES-GCM 端到端加密</h3>
              <p className="text-slate-500 leading-relaxed text-sm sm:text-base">
                局域网信道通过 ECDH 密钥协商与 AES-GCM 加密校验保护，内网公共 Wi-Fi 下同样严防窃听与篡改。
              </p>
            </div>

            <div className="bg-white p-8 rounded-[2.25rem] shadow-xl border border-slate-100 flex flex-col group hover:-translate-y-2 transition-all duration-500">
              <div className="w-16 h-16 bg-emerald-50 text-emerald-600 rounded-2xl flex items-center justify-center mb-5 group-hover:scale-110 transition duration-500">
                <QrCode className="w-8 h-8" />
              </div>
              <h3 className="text-xl font-black text-slate-900 mb-3">面对面扫码 &amp; 隐私域控制</h3>
              <p className="text-slate-500 leading-relaxed text-sm sm:text-base">
                支持设备列表自动发现或面对面扫码秒配对；可精细勾选允许同步的数据域（如屏蔽私密日记与账本），安全可控。
              </p>
            </div>

            <div className="bg-white p-8 rounded-[2.25rem] shadow-xl border border-slate-100 flex flex-col group hover:-translate-y-2 transition-all duration-500">
              <div className="w-16 h-16 bg-amber-50 text-amber-600 rounded-2xl flex items-center justify-center mb-5 group-hover:scale-110 transition duration-500">
                <FileUp className="w-8 h-8" />
              </div>
              <h3 className="text-xl font-black text-slate-900 mb-3">大文件互传 &amp; 省电联动</h3>
              <p className="text-slate-500 leading-relaxed text-sm sm:text-base">
                跨端疾速发送图片、文档与安装包；适配 macOS 与移动端低电量模式自动调整探测频率，兼顾续航与即时性。
              </p>
            </div>
          </div>

          {/* Connecting devices visualization */}
          <div className="flex flex-col lg:flex-row items-center justify-center gap-10 lg:gap-16 relative z-10 mt-20">
            <div className="w-full lg:w-7/12 max-w-[640px] group transition-transform duration-500 hover:scale-[1.02]">
              <MonitorFrame src="./lan_sync_desktop_v2.jpg" />
              <div className="mt-6 flex items-center justify-center gap-2 text-slate-400 font-bold uppercase tracking-widest text-xs">
                <Monitor className="w-4 h-4" /> macOS / Windows 局域网同步与扫码配对
              </div>
            </div>

            <div className="hidden lg:flex flex-col items-center gap-4 shrink-0">
              <div className="w-16 h-16 rounded-full bg-indigo-600 text-white flex items-center justify-center shadow-2xl shadow-indigo-200 animate-pulse">
                <ArrowLeftRight className="w-8 h-8" />
              </div>
              <div className="text-indigo-600 font-black text-xs uppercase tracking-tighter">ECDH + AES-GCM</div>
            </div>

            <div className="w-[82%] sm:w-[60%] lg:w-4/12 max-w-[320px] group transition-transform duration-500 hover:scale-[1.03] hover:-rotate-1">
              <div className="rounded-[2rem] bg-white p-2 border border-slate-200 shadow-2xl overflow-hidden">
                <img
                  src="./lan_sync_manual_domains.jpg"
                  alt="局域网手动同步按数据域选择"
                  loading="lazy"
                  className="w-full h-auto rounded-[1.5rem] object-contain"
                />
              </div>
              <div className="mt-5 flex items-center justify-center gap-2 text-slate-400 font-bold uppercase tracking-widest text-xs">
                <Smartphone className="w-4 h-4" /> 9 大数据域自选直传
              </div>
            </div>

            {/* Background Glow */}
            <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[120%] h-[120%] bg-indigo-500/5 blur-[120px] rounded-full -z-10 pointer-events-none"></div>
          </div>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-8 max-w-4xl mx-auto">
          {[
            { icon: <QrCode className="w-5 h-5 text-indigo-600 mx-auto mb-2" />, label: '面对面扫码', desc: '即扫即连零配置' },
            { icon: <ShieldCheck className="w-5 h-5 text-emerald-600 mx-auto mb-2" />, label: 'ECDH 加密', desc: 'AES-GCM 端到端保护' },
            { icon: <Zap className="w-5 h-5 text-amber-500 mx-auto mb-2" />, label: '隐私域隔离', desc: '敏感模块按需授权' },
            { icon: <BatteryCharging className="w-5 h-5 text-blue-600 mx-auto mb-2" />, label: '省电策略联动', desc: '低电量智能降频' },
          ].map((item, i) => (
            <div key={i} className="text-center">
              {item.icon}
              <div className="text-xl font-black text-slate-900 mb-1 tracking-tight">{item.label}</div>
              <div className="text-xs font-bold text-slate-400 uppercase tracking-widest">{item.desc}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};
