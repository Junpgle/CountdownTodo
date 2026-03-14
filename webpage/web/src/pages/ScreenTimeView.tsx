import { useState, useEffect } from 'react';
import {
  RefreshCw, Monitor, Smartphone, MonitorSmartphone,
  PieChart as PieChartIcon
} from 'lucide-react';
import { ApiService } from '../services/api';
import type { ScreenTimeStat, AppGroup } from './webapp-utils';
import { readDayCache, writeDayCache, formatHM, simplifyDeviceName } from './webapp-utils';

// --------------------------------------------------------
// 屏幕时间组件
// --------------------------------------------------------
export const ScreenTimeView = ({ userId }: { userId: number }) => {
  const cacheKey = `u${userId}_screen_time_${new Date().toDateString()}`;
  const cached = readDayCache<ScreenTimeStat[]>(cacheKey);

  const [stats, setStats] = useState<ScreenTimeStat[]>(cached ?? []);
  const [loading, setLoading] = useState(!cached); // 有缓存则不显示 loading
  const [filter, setFilter] = useState<'all' | 'pc' | 'mobile'>('all');
  const [selectedDate] = useState(new Date());

  useEffect(() => {
    // 有缓存直接用，不再请求 API
    if (cached) return;
    fetchStats();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const fetchStats = async () => {
    setLoading(true);
    try {
      const dateStr = selectedDate.toISOString().split('T')[0];
      const data = await ApiService.request(`/api/screen_time?user_id=${userId}&date=${dateStr}`, { method: 'GET' });
      const result = (Array.isArray(data) ? data : []) as ScreenTimeStat[];
      setStats(result);
      writeDayCache(cacheKey, result);
    } catch (e) {
      console.error("获取屏幕时间失败", e);
    } finally {
      setLoading(false);
    }
  };

  const getFilteredStats = () => {
    return stats.filter(item => {
      const dName = (item.device_name || "").toLowerCase();
      if (filter === 'all') return true;
      if (filter === 'pc') return dName.includes("windows") || dName.includes("pc") || dName.includes("lapt");
      if (filter === 'mobile') return dName.includes("phone") || dName.includes("tablet");
      return true;
    });
  };

  const filteredStats = getFilteredStats();
  const totalDuration = filteredStats.reduce((sum, item) => sum + (item.duration || 0), 0);

  const appGroups = filteredStats.reduce((acc, item) => {
    const appName = item.app_name || '未知应用';
    if (!acc[appName]) acc[appName] = { total: 0, category: item.category || '未分类', devices: {} };
    acc[appName].total += item.duration;
    acc[appName].devices[item.device_name] = (acc[appName].devices[item.device_name] || 0) + item.duration;
    return acc;
  }, {} as Record<string, AppGroup>);

  const topApps = Object.entries(appGroups)
      .map(([name, data]: [string, AppGroup]) => ({
        name,
        total: data.total,
        category: data.category,
        devices: data.devices
      }))
      .sort((a, b) => b.total - a.total);

  return (
      <div className="flex flex-col gap-6 animate-in fade-in duration-300 h-full flex-1 min-h-0">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 bg-white p-6 rounded-3xl shadow-sm border border-slate-100 shrink-0">
          <div>
            <h2 className="text-2xl font-black text-slate-800 flex items-center gap-2">
              <PieChartIcon className="w-6 h-6 text-indigo-500" />
              屏幕时间看板
            </h2>
            <p className="text-slate-500 text-sm mt-1">跨设备使用时长分析</p>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <button
                onClick={fetchStats}
                disabled={loading}
                className="p-2 bg-slate-100 hover:bg-slate-200 text-slate-500 rounded-xl transition disabled:opacity-50"
                title="刷新数据"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            </button>
            <div className="flex items-center gap-2 bg-slate-100 p-1.5 rounded-xl">
              <button onClick={() => setFilter('all')} className={`px-4 py-2 rounded-lg text-sm font-bold transition ${filter === 'all' ? 'bg-white shadow-sm text-indigo-600' : 'text-slate-500 hover:text-slate-700'}`}>全部</button>
              <button onClick={() => setFilter('pc')} className={`px-4 py-2 rounded-lg text-sm font-bold transition flex items-center gap-1 ${filter === 'pc' ? 'bg-white shadow-sm text-blue-600' : 'text-slate-500 hover:text-slate-700'}`}><Monitor className="w-4 h-4" /> 电脑</button>
              <button onClick={() => setFilter('mobile')} className={`px-4 py-2 rounded-lg text-sm font-bold transition flex items-center gap-1 ${filter === 'mobile' ? 'bg-white shadow-sm text-purple-600' : 'text-slate-500 hover:text-slate-700'}`}><Smartphone className="w-4 h-4" /> 移动端</button>
            </div>
          </div>
        </div>

        {loading ? (
            <div className="flex-1 flex items-center justify-center min-h-0">
              <RefreshCw className="w-8 h-8 text-indigo-300 animate-spin" />
            </div>
        ) : (
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 flex-1 min-h-0">
              <div className="lg:col-span-1 bg-gradient-to-br from-indigo-500 to-purple-600 rounded-3xl p-8 text-white shadow-lg relative overflow-hidden flex flex-col justify-center min-h-[200px] lg:min-h-0 shrink-0">
                <div className="absolute -right-10 -top-10 text-white/10">
                  <MonitorSmartphone className="w-48 h-48" />
                </div>
                <div className="relative z-10">
                  <p className="text-indigo-100 font-bold mb-2 text-lg">今日总计使用</p>
                  <div className="text-5xl font-black mb-4 tracking-tight">
                    {formatHM(totalDuration).replace('小时', 'h').replace('分钟', 'm')}
                  </div>
                  <p className="text-sm text-indigo-100/80 bg-black/20 inline-block px-3 py-1 rounded-full">
                    {selectedDate.toLocaleDateString()} 数据
                  </p>
                </div>
              </div>
              <div className="lg:col-span-2 bg-white rounded-3xl shadow-sm border border-slate-100 overflow-hidden flex flex-col min-h-[400px] lg:min-h-0">
                <div className="p-6 border-b border-slate-100 bg-slate-50/50 flex justify-between items-center shrink-0">
                  <h3 className="font-bold text-lg text-slate-800">最常使用应用</h3>
                  <span className="text-sm font-bold text-slate-400">{topApps.length} 个应用</span>
                </div>
                <div className="p-2 flex-1 overflow-y-auto min-h-0">
                  {topApps.length === 0 ? (
                      <div className="h-full flex flex-col items-center justify-center py-20 text-slate-400">
                        <PieChartIcon className="w-12 h-12 mb-4 opacity-20" />
                        <p>暂无使用数据</p>
                      </div>
                  ) : (
                      <div className="space-y-1">
                        {topApps.map((app, idx) => (
                            <div key={app.name} className="flex items-center gap-4 p-4 hover:bg-slate-50 rounded-2xl transition group">
                              <div className="w-12 h-12 rounded-xl bg-indigo-50 text-indigo-600 flex items-center justify-center font-black text-xl shrink-0">{idx + 1}</div>
                              <div className="flex-1 min-w-0">
                                <p className="font-bold text-slate-800 truncate text-base">{app.name}</p>
                                <div className="flex gap-2 mt-1">
                                  {Object.entries(app.devices).map(([dev]) => (
                                      <span key={dev} className="text-[11px] font-medium bg-slate-100 text-slate-500 px-2 py-0.5 rounded-md flex items-center gap-1">{simplifyDeviceName(dev)}</span>
                                  ))}
                                </div>
                              </div>
                              <div className="text-right shrink-0">
                                <p className="font-black text-lg text-slate-700">{formatHM(app.total).replace('分钟','m').replace('小时','h')}</p>
                                <p className="text-[11px] text-slate-400">{app.category}</p>
                              </div>
                            </div>
                        ))}
                      </div>
                  )}
                </div>
              </div>
            </div>
        )}
      </div>
  );
};
